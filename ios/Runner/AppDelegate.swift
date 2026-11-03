import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var nativeDialogs: FlutterMethodChannel?
  private var sfSymbols: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NativeDialogs") else { return }
    let channel = FlutterMethodChannel(name: "liftmate/native_dialogs", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      NativeDialogs.handle(call, result: result)
    }
    nativeDialogs = channel
    let symbols = FlutterMethodChannel(name: "liftmate/sf_symbol", binaryMessenger: registrar.messenger())
    symbols.setMethodCallHandler { call, result in
      SfSymbolRenderer.handle(call, result: result)
    }
    sfSymbols = symbols
    registrar.register(NativeGlassFactory(messenger: registrar.messenger(), surface: false), withId: "liftmate/glass_button")
    registrar.register(NativeGlassFactory(messenger: registrar.messenger(), surface: true), withId: "liftmate/glass_surface")
    registrar.register(NativeSwitchFactory(messenger: registrar.messenger()), withId: "liftmate/switch")
  }
}

// Vẽ SF Symbol thành PNG trắng; Flutter tô lại màu theo chỗ dùng
private enum SfSymbolRenderer {
  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "png",
      let name = (call.arguments as? [String: Any])?["name"] as? String,
      let symbol = UIImage(
        systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 96, weight: .regular))?
        .withTintColor(.white, renderingMode: .alwaysOriginal)
    else {
      result(nil)
      return
    }
    let side = max(symbol.size.width, symbol.size.height)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 2
    format.opaque = false
    let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
      symbol.draw(at: CGPoint(x: (side - symbol.size.width) / 2, y: (side - symbol.size.height) / 2))
    }
    guard let png = image.pngData() else {
      result(nil)
      return
    }
    result(FlutterStandardTypedData(bytes: png))
  }
}

private final class NativeSwitchFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    return NativeSwitch(frame: frame, viewId: viewId, args: args as? [String: Any] ?? [:], messenger: messenger)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}

// Công tắc thật của iOS (UISwitch). Gạt thì báo về Dart; Dart gửi "update" để đồng bộ giá trị và trạng thái khóa.
private final class NativeSwitch: NSObject, FlutterPlatformView {
  private let container: UIView
  private let control = UISwitch()
  private let channel: FlutterMethodChannel

  init(frame: CGRect, viewId: Int64, args: [String: Any], messenger: FlutterBinaryMessenger) {
    container = UIView(frame: frame)
    channel = FlutterMethodChannel(name: "liftmate/switch_\(viewId)", binaryMessenger: messenger)
    super.init()
    control.isOn = args["value"] as? Bool ?? false
    control.isEnabled = args["enabled"] as? Bool ?? true
    if let color = args["color"] as? NSNumber {
      let argb = color.uint32Value
      control.onTintColor = UIColor(
        red: CGFloat((argb >> 16) & 0xFF) / 255,
        green: CGFloat((argb >> 8) & 0xFF) / 255,
        blue: CGFloat(argb & 0xFF) / 255,
        alpha: 1
      )
    }
    control.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(control)
    NSLayoutConstraint.activate([
      control.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      control.centerYAnchor.constraint(equalTo: container.centerYAnchor),
    ])
    control.addAction(
      UIAction { [weak self] _ in
        guard let self else { return }
        self.channel.invokeMethod("changed", arguments: self.control.isOn)
      }, for: .valueChanged)
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "update", let args = call.arguments as? [String: Any] {
        self?.control.setOn(args["value"] as? Bool ?? false, animated: true)
        self?.control.isEnabled = args["enabled"] as? Bool ?? true
      }
      result(nil)
    }
  }

  func view() -> UIView {
    return container
  }
}

private final class NativeGlassFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  private let surface: Bool

  init(messenger: FlutterBinaryMessenger, surface: Bool) {
    self.messenger = messenger
    self.surface = surface
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    if surface {
      return NativeGlassSurface(frame: frame, args: args as? [String: Any] ?? [:])
    }
    return NativeGlassButton(frame: frame, viewId: viewId, args: args as? [String: Any] ?? [:], messenger: messenger)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}

// Lớp màu phủ lên kính native để đỡ trong suốt, chữ và biểu tượng dễ đọc trên bản đồ. Tăng alpha thì đục hơn.
private func nativeGlassTint(alpha: CGFloat) -> UIColor {
  return UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.17, green: 0.17, blue: 0.18, alpha: alpha)
      : UIColor(white: 1, alpha: alpha)
  }
}

// Nền kính thật của iOS 26 hình viên thuốc, chữ và biểu tượng do Flutter vẽ đè lên. Bản cũ hơn dùng vật liệu mờ.
private final class NativeGlassSurface: NSObject, FlutterPlatformView {
  private let glass: UIVisualEffectView

  // cornerRadius: góc bo cố định (sheet); không truyền thì hình viên thuốc
  init(frame: CGRect, args: [String: Any]) {
    let cornerRadius = (args["cornerRadius"] as? NSNumber).map { CGFloat($0.doubleValue) }
    if #available(iOS 26.0, *) {
      let effect = UIGlassEffect()
      effect.tintColor = nativeGlassTint(alpha: (args["tintAlpha"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0.62)
      glass = UIVisualEffectView(effect: effect)
      glass.cornerConfiguration = cornerRadius.map { .corners(radius: .fixed($0)) } ?? .capsule()
    } else {
      glass = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
      glass.layer.cornerRadius = cornerRadius ?? 24
      glass.clipsToBounds = true
    }
    glass.frame = frame
    super.init()
  }

  func view() -> UIView {
    return glass
  }
}

// Nút biểu tượng thật của iOS: Liquid Glass từ iOS 26, nút xám tròn ở bản cũ hơn. Bấm thì báo về Dart.
private final class NativeGlassButton: NSObject, FlutterPlatformView {
  private let button: UIButton
  private let channel: FlutterMethodChannel

  init(frame: CGRect, viewId: Int64, args: [String: Any], messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "liftmate/glass_button_\(viewId)", binaryMessenger: messenger)
    var config: UIButton.Configuration
    if #available(iOS 26.0, *) {
      // Kiểu glass thường không nhận màu nền; kiểu prominent lấy tintColor của nút làm lớp màu phủ
      config = .prominentGlass()
    } else {
      config = .gray()
    }
    config.cornerStyle = .capsule
    config.contentInsets = .zero
    let pointSize = (args["pointSize"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 17
    let image = UIImage(
      systemName: args["symbol"] as? String ?? "chevron.left",
      withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
    )
    // Kiểu glass bỏ qua baseForegroundColor: muốn có màu riêng thì tô thẳng vào ảnh
    if let symbolColor = (args["foreground"] as? NSNumber) ?? (args["tint"] as? NSNumber) {
      config.image = image?.withTintColor(NativeGlassButton.color(symbolColor.uint32Value), renderingMode: .alwaysOriginal)
    } else {
      config.image = image
    }
    button = UIButton(configuration: config)
    button.frame = frame
    button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    if #available(iOS 26.0, *) {
      button.tintColor = nativeGlassTint(alpha: 0.62)
    } else if let tint = args["tint"] as? NSNumber {
      button.tintColor = NativeGlassButton.color(tint.uint32Value)
    }
    button.accessibilityLabel = args["label"] as? String
    super.init()
    // Có danh sách thì bấm là mở menu thật của iOS ngay tại nút, như nút "…" của Ghi chú
    if let items = args["menu"] as? [[String: Any]] {
      button.menu = UIMenu(children: items.enumerated().map { index, item in
        let symbol = item["symbol"] as? String
        return UIAction(
          title: item["title"] as? String ?? "",
          image: symbol.flatMap { UIImage(systemName: $0) },
          attributes: (item["destructive"] as? Bool) == true ? .destructive : []
        ) { [weak self] _ in
          self?.channel.invokeMethod("menu", arguments: index)
        }
      })
      button.showsMenuAsPrimaryAction = true
      if #available(iOS 16.0, *) {
        button.preferredMenuElementOrder = .fixed
      }
    } else {
      button.addAction(
        UIAction { [weak self] _ in
          self?.channel.invokeMethod("tap", arguments: nil)
        }, for: .touchUpInside)
    }
  }

  func view() -> UIView {
    return button
  }

  private static func color(_ argb: UInt32) -> UIColor {
    return UIColor(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255
    )
  }
}

// Hộp thoại và menu chọn thật của iOS (UIAlertController), Dart gọi qua showIosConfirm / showIosActionSheet.
// Trả về vị trí nút đã bấm trong actions, nil khi bấm Hủy.
private enum NativeDialogs {
  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "alert" || call.method == "sheet",
      let args = call.arguments as? [String: Any],
      let actions = args["actions"] as? [[String: String]]
    else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let presenter = topViewController() else {
      result(nil)
      return
    }
    let isSheet = call.method == "sheet"
    let controller = UIAlertController(
      title: args["title"] as? String,
      message: args["message"] as? String,
      preferredStyle: isSheet ? .actionSheet : .alert
    )
    for (index, action) in actions.enumerated() {
      let style = action["style"]
      let alertStyle: UIAlertAction.Style =
        style == "cancel" ? .cancel : (style == "destructive" ? .destructive : .default)
      controller.addAction(
        UIAlertAction(title: action["label"], style: alertStyle) { _ in
          result(style == "cancel" ? nil : index)
        })
    }
    // iPad và iOS 26 trở lên hiện action sheet dạng popover, phải có điểm neo. Có nút nguồn thì menu bật ra từ nút đó
    if let popover = controller.popoverPresentationController {
      popover.sourceView = presenter.view
      if let anchor = args["anchor"] as? [String: Double],
        let x = anchor["x"], let y = anchor["y"], let width = anchor["width"], let height = anchor["height"]
      {
        popover.sourceRect = CGRect(x: x, y: y, width: width, height: height)
        popover.permittedArrowDirections = .up
      } else {
        popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.maxY, width: 0, height: 0)
        popover.permittedArrowDirections = []
      }
    }
    presenter.present(controller, animated: true)
  }

  private static func topViewController() -> UIViewController? {
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}
