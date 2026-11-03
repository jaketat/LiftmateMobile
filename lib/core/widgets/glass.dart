// Khối "kính mờ" kiểu Apple Liquid Glass: làm mờ nền phía sau, phủ trắng trong,
// viền sáng mảnh, bóng đổ mềm. Dùng cho app tài xế nổi trên bản đồ (canvas trang "Tài xế").
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show TargetPlatform, ValueListenable, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'page_transition.dart';

/// Bỏ làm mờ nền, thay bằng nền trắng gần đục. Android: GPU tầm trung không gánh nổi nhiều lớp mờ trên bản đồ.
/// iOS: dùng cùng kiểu để giao diện giống Android. Riêng thanh tab vẫn giữ kính thật vì chỉ tốn một lớp nhỏ.
bool get glassBlurEnabled => false;

/// iOS: dùng thanh tab, bộ lọc, công tắc của gói liquid_glass_widgets. Android giữ bản Flutter tự vẽ.
bool get useNativeControls => defaultTargetPlatform == TargetPlatform.iOS;

/// Được dựng view native (UiKitView) ở đây không. Trang đang trượt thì dùng bản Flutter vẽ, trang đứng yên mới dùng nút thật.
bool nativeViewsAllowed(BuildContext context) => useNativeControls && !RouteMotionGate.movingOf(context);

/// Bộ lọc nền của kính. iOS: bản đồ là view native, chỉ ImageFilter.blur thuần làm mờ được nó;
/// bọc compose với tăng màu thì mất mờ, chữ trên bản đồ đè lên chữ của app.
ImageFilter glassBackdropFilter(double sigma, ColorFilter saturate) {
  final ImageFilter blur = ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
  if (defaultTargetPlatform == TargetPlatform.iOS) return blur;
  return ImageFilter.compose(outer: saturate, inner: blur);
}

/// Đổi giữa nút native và bản Flutter vẽ. View native cần vài khung mới hiện, nên bản Flutter
/// vẫn nằm trên rồi mờ dần, nút không biến mất trong tích tắc. Android chỉ có bản Flutter.
class NativeSwap extends StatelessWidget {
  final Widget Function() native;
  final Widget fallback;

  const NativeSwap({super.key, required this.native, required this.fallback});

  @override
  Widget build(BuildContext context) {
    if (!useNativeControls) return fallback;
    final bool allowed = nativeViewsAllowed(context);
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        if (allowed) Positioned.fill(child: native()),
        IgnorePointer(
          ignoring: allowed,
          child: AnimatedOpacity(
            opacity: allowed ? 0 : 1,
            duration: allowed ? const Duration(milliseconds: 250) : Duration.zero,
            child: fallback,
          ),
        ),
      ],
    );
  }
}

/// Một dòng trong menu thật của iOS mở từ [NativeGlassButton]. [symbol] là tên SF Symbol.
class NativeMenuItem {
  final String label;
  final String? symbol;
  final bool destructive;

  const NativeMenuItem(this.label, {this.symbol, this.destructive = false});
}

/// Nút biểu tượng thật của iOS (UIButton glass), phần native nằm trong ios/Runner/AppDelegate.swift.
/// [symbol] là tên SF Symbol.
class NativeGlassButton extends StatefulWidget {
  final String symbol;
  final String label;
  final double size;
  final VoidCallback? onPressed;
  // Màu biểu tượng; không truyền thì theo màu mặc định của hệ thống
  final Color? foreground;
  final double iconSize;
  // Có [menu] thì bấm là mở menu ngay tại nút; chọn dòng nào thì báo vị trí dòng đó qua [onMenu]
  final List<NativeMenuItem>? menu;
  final ValueChanged<int>? onMenu;

  const NativeGlassButton({
    super.key,
    required this.symbol,
    required this.label,
    required this.size,
    required this.onPressed,
    this.foreground,
    this.iconSize = 17,
    this.menu,
    this.onMenu,
  });

  @override
  State<NativeGlassButton> createState() => _NativeGlassButtonState();
}

class _NativeGlassButtonState extends State<NativeGlassButton> {
  @override
  Widget build(BuildContext context) {
    final List<NativeMenuItem>? menu = widget.menu;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      // Màu, biểu tượng và menu nằm bên native: đổi chế độ sáng / tối, đổi biểu tượng hay đổi menu thì tạo lại nút
      child: UiKitView(
        key: ValueKey<String>('${widget.symbol}-${AppColors.isDark}-${menu?.map((NativeMenuItem item) => item.label).join('|')}'),
        viewType: 'liftmate/glass_button',
        creationParams: <String, Object?>{
          'symbol': widget.symbol,
          'tint': AppColors.navy.toARGB32(),
          'label': widget.label,
          'pointSize': widget.iconSize,
          if (widget.foreground != null) 'foreground': widget.foreground!.toARGB32(),
          if (menu != null)
            'menu': <Map<String, Object?>>[
              for (final NativeMenuItem item in menu) <String, Object?>{'title': item.label, 'symbol': item.symbol, 'destructive': item.destructive},
            ],
        },
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (int id) {
          // Đọc widget lúc bấm, không giữ hàm của lần dựng đầu: đơn đã tải lại thì phải dùng dữ liệu mới
          MethodChannel('liftmate/glass_button_$id').setMethodCallHandler((MethodCall call) async {
            if (!mounted) return;
            if (call.method == 'tap') widget.onPressed?.call();
            if (call.method == 'menu') widget.onMenu?.call(call.arguments as int);
          });
        },
      ),
    );
  }
}

/// Nền sheet kiểu Find My. iOS: kính thật của hệ thống, thấy bản đồ mờ phía sau; kéo sheet lên cao thì đục dần ([raised]).
/// Trang đang trượt thì dùng nền Flutter vẽ. [child] luôn nằm cùng một chỗ trong cây, đổi nền không làm mất vị trí cuộn.
class GlassSheetSurface extends StatelessWidget {
  static const double radius = 32;
  // Độ đục lớp màu trên kính lúc sheet ở mức thấp. Tăng thì chữ dễ đọc hơn, giảm thì thấy bản đồ rõ hơn
  static const double tintAlpha = 0.42;

  // Chiều cao sheet, tính theo phần của màn hình
  final ValueListenable<double> raised;
  // Màu phủ lên sheet: lúc thấp gần như trong, lúc kéo lên cao gần như đục
  final Color fill;
  final Widget child;

  const GlassSheetSurface({super.key, required this.raised, required this.fill, required this.child});

  @override
  Widget build(BuildContext context) {
    const BorderRadius corners = BorderRadius.vertical(top: Radius.circular(radius));
    final bool native = nativeViewsAllowed(context);
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned.fill(
          child: native
              // Giữ nguyên cỡ bằng cả màn: kéo sheet chỉ dịch view native, không phải đổi kích thước kính theo từng khung
              ? OverflowBox(
                  alignment: Alignment.topCenter,
                  minHeight: MediaQuery.sizeOf(context).height,
                  maxHeight: MediaQuery.sizeOf(context).height,
                  child: const IgnorePointer(
                    child: UiKitView(
                      viewType: 'liftmate/glass_surface',
                      creationParams: <String, Object?>{'cornerRadius': radius, 'tintAlpha': tintAlpha},
                      creationParamsCodec: StandardMessageCodec(),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        // Trượt xong thì nền Flutter mờ dần để lộ kính, không đổi đột ngột. Bắt đầu trượt thì hiện ngay
        Positioned.fill(
          child: AnimatedOpacity(
            opacity: native ? 0 : 1,
            duration: native ? const Duration(milliseconds: 250) : Duration.zero,
            child: const Glass(borderRadius: corners, opacity: 0.62, child: SizedBox.expand()),
          ),
        ),
        ClipRRect(
          borderRadius: corners,
          child: ValueListenableBuilder<double>(
            valueListenable: raised,
            builder: (BuildContext context, double size, Widget? content) {
              final double opaque = ((size - 0.5) / 0.35).clamp(0.0, 1.0);
              return ColoredBox(color: fill.withValues(alpha: 0.12 + opaque * 0.82), child: content);
            },
            child: child,
          ),
        ),
      ],
    );
  }
}

/// Viền kính vẽ đè lên mép khối: đường tối rất mảnh ngoài cùng để tách khỏi nền sáng,
/// rồi dải sáng chạy chéo như cạnh kính dày bắt sáng, để khối tách bạch trên mọi nền.
class GlassRimPainter extends CustomPainter {
  final BorderRadius borderRadius;

  const GlassRimPainter(this.borderRadius);

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final RRect shape = borderRadius.toRRect(rect);
    canvas.drawRRect(
      shape.deflate(0.25),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = AppColors.isDark ? const Color(0x33FFFFFF) : const Color(0x24101828),
    );
    canvas.drawRRect(
      shape.deflate(1.2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const <double>[0, 0.3, 0.55, 0.8, 1],
          // Chế độ tối: cạnh kính chỉ bắt sáng nhẹ, không thành viền trắng
          colors: <Color>[
            Colors.white.withValues(alpha: AppColors.isDark ? 0.22 : 1),
            Colors.white.withValues(alpha: AppColors.isDark ? 0.1 : 0.55),
            Colors.white.withValues(alpha: AppColors.isDark ? 0.05 : 0.25),
            Colors.white.withValues(alpha: AppColors.isDark ? 0.1 : 0.6),
            Colors.white.withValues(alpha: AppColors.isDark ? 0.2 : 0.95),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(GlassRimPainter oldDelegate) => true;
}

class Glass extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  // Độ đục của lớp trắng (0.5–0.8). Cao hơn khi chữ cần đọc rõ trên nền bản đồ rối.
  final double opacity;
  final double blur;
  final bool shadow;
  // iOS: nền kính thật của hệ thống (UIGlassEffect) hình viên thuốc, nội dung Flutter vẽ đè lên
  final bool nativeSurface;

  const Glass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.padding,
    this.opacity = 0.6,
    this.blur = 26,
    this.shadow = true,
    this.nativeSurface = false,
  });

  // Tăng độ bão hòa màu phía sau kính (như Liquid Glass: bản đồ sau kính vẫn tươi, không xám đục)
  static const ColorFilter _saturate = ColorFilter.matrix(<double>[
    1.5511, -0.5005, -0.0504, 0, 0, //
    -0.1491, 1.1995, -0.0504, 0, 0, //
    -0.1491, -0.5005, 1.6496, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    if (nativeSurface && useNativeControls) {
      final bool native = nativeViewsAllowed(context);
      return Stack(
        children: <Widget>[
          Positioned.fill(
            child: native
                ? const IgnorePointer(
                    child: UiKitView(viewType: 'liftmate/glass_surface', creationParamsCodec: StandardMessageCodec()),
                  )
                : const SizedBox.shrink(),
          ),
          // View native cần vài khung mới hiện: giữ nền Flutter rồi mờ dần, không để khối mất nền trong tích tắc
          Positioned.fill(
            child: AnimatedOpacity(
              opacity: native ? 0 : 1,
              duration: native ? const Duration(milliseconds: 250) : Duration.zero,
              child: Glass(borderRadius: borderRadius, opacity: opacity, shadow: shadow, child: const SizedBox.expand()),
            ),
          ),
          padding == null ? child : Padding(padding: padding!, child: child),
        ],
      );
    }
    if (!glassBlurEnabled) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          color: AppColors.glass.withValues(alpha: (0.7 + opacity * 0.3).clamp(0.0, 1.0)),
          boxShadow: shadow
              ? const <BoxShadow>[BoxShadow(color: Color(0x1F0C2858), blurRadius: 30, offset: Offset(0, 10))]
              : null,
        ),
        child: CustomPaint(
          foregroundPainter: GlassRimPainter(borderRadius),
          child: ClipRRect(
            borderRadius: borderRadius,
            child: padding == null ? child : Padding(padding: padding!, child: child),
          ),
        ),
      );
    }
    // Liquid Glass: lớp trắng theo đúng [opacity] để nền sáng, chữ đọc được cả trên bản đồ vệ tinh tối;
    // làm mờ nền, viền sáng mảnh và vệt bóng ở mép trên vẫn giữ cảm giác trong.
    final double base = opacity.clamp(0.0, 1.0);
    final double top = (base + 0.14).clamp(0.0, 1.0);
    final double sigma = blur * 0.6;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: shadow
            ? const <BoxShadow>[BoxShadow(color: Color(0x1F0C2858), blurRadius: 30, offset: Offset(0, 10))]
            : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: glassBackdropFilter(sigma, _saturate),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              // Ánh sáng từ trên xuống: mép trên sáng hơn, như mặt kính cong
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const <double>[0, 0.35, 1],
                colors: <Color>[
                  Colors.white.withValues(alpha: top),
                  Colors.white.withValues(alpha: base),
                  Colors.white.withValues(alpha: base * 0.85),
                ],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 0.8),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Nút tròn kính mờ (quay lại, về vị trí của tôi)
class GlassCircleButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final Color color;
  // iOS: có tên SF Symbol thì dùng nút thật của hệ thống
  final String? nativeSymbol;

  GlassCircleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 52,
    this.nativeSymbol,
    Color? color,
  }) : color = color ?? AppColors.navy;

  @override
  Widget build(BuildContext context) {
    final Widget fallback = Semantics(
      button: true,
      label: tooltip,
      child: Glass(
        borderRadius: BorderRadius.circular(size / 2),
        child: SizedBox(
          width: size,
          height: size,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: Tooltip(message: tooltip, child: Icon(icon, color: color, size: 24)),
            ),
          ),
        ),
      ),
    );
    if (nativeSymbol == null) return fallback;
    return NativeSwap(
      native: () => NativeGlassButton(symbol: nativeSymbol!, label: tooltip, size: size, onPressed: onPressed),
      fallback: fallback,
    );
  }
}

/// Viên nhỏ có chấm màu, vd "Đang chia sẻ · 08:31"
class GlassChip extends StatelessWidget {
  final String text;
  final Color dotColor;
  final Color textColor;
  final VoidCallback? onTap;

  const GlassChip({
    super.key,
    required this.text,
    required this.dotColor,
    required this.textColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Glass(
      borderRadius: BorderRadius.circular(999),
      opacity: 0.7,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      text,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Thanh "kéo" xám ở đầu sheet
class SheetGrabber extends StatelessWidget {
  const SheetGrabber({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 8),
        width: 40,
        height: 5,
        decoration: BoxDecoration(color: AppColors.isDark ? const Color(0x4DFFFFFF) : const Color(0x38101828), borderRadius: BorderRadius.circular(99)),
      ),
    );
  }
}

class GlassTabItem {
  final IconData icon;
  // Biểu tượng tô đặc khi tab được chọn (iOS 26: chọn thì icon đặc, màu nhấn)
  final IconData selectedIcon;
  final String label;
  // Tên SF Symbol cho thanh tab native trên iOS
  final String? sfSymbol;

  const GlassTabItem({required this.icon, required this.selectedIcon, required this.label, this.sfSymbol});
}

/// Thanh tab nổi theo iOS 26 Liquid Glass:
/// - Viên kính nổi cách mép, không dính đáy màn.
/// - Tab đang chọn nằm trong một "thấu kính" kính sáng hơn, trượt mượt sang tab mới.
/// - Icon tab chọn tô đặc, màu nhấn; tab khác icon nét, màu chữ.
/// - Nhấn giữ thì thấu kính phồng nhẹ (phản hồi như kính lỏng).
class GlassTabBar extends StatefulWidget {
  static const double barHeight = 64;

  final List<GlassTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Color accent;
  // Thu nhỏ khi cuộn: thấp hơn, biểu tượng nhỏ lại, ẩn chữ
  final bool compact;

  GlassTabBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.compact = false,
    // Navy của LiftMate cho tab đang chọn
    Color? accent,
  }) : accent = accent ?? AppColors.navy;

  @override
  State<GlassTabBar> createState() => _GlassTabBarState();
}

/// Thanh tab trắng sáng hơi trong, bóng mềm để tách khỏi nội dung phía sau,
/// thấu kính xám nhạt của tab đang chọn trượt theo tab và phồng khi nhấn.
class _GlassTabBarState extends State<GlassTabBar> {
  static const double barHeight = GlassTabBar.barHeight;
  // Lớp trắng phủ trên kính: càng thấp càng trong. Là số ước lượng theo mắt.
  static const double tabBarFillOpacity = 0.6;
  static const double lensInset = 4;
  int? pressedIndex;
  // Tâm thấu kính khi ngón tay đang rê trên thanh; null: không rê, thấu kính nằm ở tab đang chọn
  double? dragX;
  // Vừa rê chọn tab, đang chờ màn đổi: giữ thấu kính ở tab mới, không chạy ngược về tab cũ
  int? settlingIndex;

  static const double compactHeight = 50;

  @override
  void didUpdateWidget(covariant GlassTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex == settlingIndex) {
      settlingIndex = null;
    }
  }

  int _tabAt(double x, double tabWidth, int count) {
    return ((x - lensInset) / tabWidth).floor().clamp(0, count - 1);
  }

  void _moveDrag(double x, double tabWidth, int count) {
    final int? before = dragX == null ? null : _tabAt(dragX!, tabWidth, count);
    final int after = _tabAt(x, tabWidth, count);
    if (before != null && before != after) {
      HapticFeedback.selectionClick();
    }
    setState(() {
      settlingIndex = null;
      dragX = x;
    });
  }

  void _endDrag(double tabWidth, int count) {
    final double? x = dragX;
    if (x == null) return;
    final int target = _tabAt(x, tabWidth, count);
    setState(() {
      dragX = null;
      settlingIndex = target == widget.selectedIndex ? null : target;
    });
    if (target != widget.selectedIndex) {
      widget.onSelected(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: widget.compact ? 1 : 0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double t, Widget? _) => _bar(context, t),
    );
  }

  Widget _bar(BuildContext context, double t) {
    final int count = widget.items.length;
    final int selected = (settlingIndex ?? widget.selectedIndex).clamp(0, count - 1);
    final bool dragging = dragX != null;
    final bool lensPressed = dragging || pressedIndex == selected;
    final BorderRadius radius = BorderRadius.circular(999);
    final double height = barHeight + (compactHeight - barHeight) * t;
    final double iconSize = 26 - 4 * t;

    final Widget content = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double tabWidth = (constraints.maxWidth - lensInset * 2) / count;
        // Đang rê: thấu kính bám ngón tay, tab dưới ngón tay sáng lên; buông tay mới chọn
        final int highlighted = dragging ? _tabAt(dragX!, tabWidth, count) : selected;
        final double lensLeft = dragging
            ? (dragX! - tabWidth / 2).clamp(lensInset, lensInset + tabWidth * (count - 1))
            : lensInset + tabWidth * selected;
        final List<Widget> tabs = <Widget>[];
        for (int index = 0; index < count; index++) {
          final GlassTabItem item = widget.items[index];
          final bool on = index == highlighted;
          final Color color = on ? widget.accent : AppColors.text;
          tabs.add(
            SizedBox(
              width: tabWidth,
              child: Semantics(
                button: true,
                selected: on,
                label: item.label,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) => setState(() => pressedIndex = index),
                  onTapCancel: () => setState(() => pressedIndex = null),
                  onTapUp: (_) => setState(() => pressedIndex = null),
                  onTap: () => widget.onSelected(index),
                  child: AnimatedScale(
                    scale: pressedIndex == index ? 0.92 : 1,
                    duration: const Duration(milliseconds: 120),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(on ? item.selectedIcon : item.icon, size: iconSize, color: color),
                        // Chữ thu lại và mờ dần khi thanh nhỏ
                        ClipRect(
                          child: Align(
                            alignment: Alignment.topCenter,
                            heightFactor: 1 - t,
                            child: Opacity(
                              opacity: (1 - t * 1.6).clamp(0.0, 1.0),
                              child: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  item.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color, letterSpacing: 0.1),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (DragStartDetails details) => _moveDrag(details.localPosition.dx, tabWidth, count),
          onHorizontalDragUpdate: (DragUpdateDetails details) => _moveDrag(details.localPosition.dx, tabWidth, count),
          onHorizontalDragEnd: (DragEndDetails _) => _endDrag(tabWidth, count),
          onHorizontalDragCancel: () => setState(() => dragX = null),
          child: Stack(
          children: <Widget>[
            // Thấu kính tab đang chọn: viên xám nhạt trên nền trắng, không viền, không bóng đổ
            AnimatedPositioned(
              // Đang rê thì bám sát ngón tay; buông tay mới trượt nảy về tab
              duration: Duration(milliseconds: dragging ? 70 : 380),
              curve: dragging ? Curves.linear : Curves.easeOutBack,
              left: lensLeft - (lensPressed ? 4 : 0),
              top: lensInset - (lensPressed ? 4 : 0),
              width: tabWidth + (lensPressed ? 8 : 0),
              height: constraints.maxHeight - lensInset * 2 + (lensPressed ? 8 : 0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  color: const Color(0xFF787880).withValues(alpha: 0.14),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: lensInset),
              child: Row(children: tabs),
            ),
          ],
          ),
        );
      },
    );

    return DecoratedBox(
      // Bóng rộng và mềm để thanh tách khỏi nội dung phía sau
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x33000000), blurRadius: 28, offset: Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          // Mờ + tăng màu: thấy thoáng màu phía sau nhưng chữ và icon không bị nội dung đè lên
          filter: glassBackdropFilter(18, Glass._saturate),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              borderRadius: radius,
              color: AppColors.glass.withValues(alpha: tabBarFillOpacity),
              // Đường tối rất mảnh ở mép, giữ được hình thanh khi nền phía sau cũng trắng
              border: Border.all(color: (AppColors.isDark ? Colors.white : Colors.black).withValues(alpha: 0.12), width: 0.5),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}
