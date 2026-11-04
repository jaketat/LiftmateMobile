// Giao diện của LiftMate Intelligence, phong cách Apple Intelligence: viền sáng cả màn, ô có quầng màu, chữ gradient, chữ chạy sáng, dòng chờ cầu vồng.
// Công thức màu và thời gian lấy từ AppleIntelligenceForSwiftUI, Copyright 2025 Alessio Rubicini, giấy phép MIT.
// Viết lại bằng Dart vì gói gốc là SwiftUI, chỉ chạy iOS 26 trở lên; nhúng vào Flutter thì Android không có.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

import '../theme.dart';
import 'ios.dart';

// Màu lấy từ chữ "Apple Intelligence" trong ảnh mẫu, đọc từ trái sang phải
const List<Color> aiTextColors = <Color>[
  Color(0xFF109DF7),
  Color(0xFF2698F7),
  Color(0xFF6E82FA),
  Color(0xFFC265F8),
  Color(0xFFE15DD0),
  Color(0xFFF15D97),
  Color(0xFFF75E5F),
  Color(0xFFF97A32),
  Color(0xFFF99911),
];

/// Nền ô nhập trong khu vực LiftMate Intelligence: màu bề mặt pha nhạt dải màu, cùng độ pha với nền nút
BoxDecoration aiFieldDecoration({required double radius, BoxBorder? border}) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    border: border,
    gradient: LinearGradient(
      colors: <Color>[for (final Color color in aiTextColors) Color.alphaBlend(color.withValues(alpha: aiTintOpacity), AppColors.surface)],
    ),
  );
}

const double aiTintOpacity = 0.14;

/// Chữ của khu vực LiftMate Intelligence: SF của iOS như ảnh mẫu, Android dùng Roboto là phông gần nhất.
/// Màu trắng để AiGradient đổ dải màu lên.
TextStyle aiTextStyle(double fontSize, {FontWeight fontWeight = FontWeight.w500}) {
  final bool ios = defaultTargetPlatform == TargetPlatform.iOS;
  return TextStyle(
    fontFamily: ios ? (fontSize >= 20 ? 'CupertinoSystemDisplay' : 'CupertinoSystemText') : 'Roboto',
    fontSize: fontSize,
    fontWeight: fontWeight,
    letterSpacing: fontSize >= 20 ? -0.4 : -0.2,
    color: Colors.white,
  );
}

/// Vòng màu của quầng sáng, cùng họ với chữ, không có xanh lá; màu đầu lặp ở cuối để vòng khép kín
const List<Color> aiGlowColors = <Color>[
  Color(0xFF109DF7),
  Color(0xFFC265F8),
  Color(0xFFE15DD0),
  Color(0xFFF75E5F),
  Color(0xFFF99911),
  Color(0xFFF15D97),
  Color(0xFF6E82FA),
  Color(0xFF109DF7),
];

/// Vòng màu xoay đều theo [phase], như ô soạn của Siri
SweepGradient aiSweepGradient(double phase) {
  return SweepGradient(colors: aiGlowColors, transform: _StretchedRotation((phase * 40 % 360) * math.pi / 180));
}

/// Xoay vòng màu rồi kéo theo tỉ lệ khung. Không kéo thì trên khung dẹt, đoạn giữa cạnh dài đổi màu gắt thành vệt.
class _StretchedRotation extends GradientTransform {
  final double radians;

  const _StretchedRotation(this.radians);

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final double side = math.max(1, bounds.shortestSide);
    return Matrix4.translationValues(bounds.center.dx, bounds.center.dy, 0)
      ..multiply(Matrix4.diagonal3Values(bounds.width / side, bounds.height / side, 1))
      ..multiply(Matrix4.rotationZ(radians))
      ..multiply(Matrix4.translationValues(-bounds.center.dx, -bounds.center.dy, 0));
  }
}

/// Đồng hồ 30 khung/giây cho hiệu ứng sáng: nhanh hơn không thấy khác mà tốn pin. Tắt giảm chuyển động thì đứng yên.
class _GlowClock extends StatefulWidget {
  final Widget Function(ValueListenable<double> seconds) builder;

  const _GlowClock({required this.builder});

  @override
  State<_GlowClock> createState() => _GlowClockState();
}

class _GlowClockState extends State<_GlowClock> with SingleTickerProviderStateMixin {
  final ValueNotifier<double> seconds = ValueNotifier<double>(0);
  late final Ticker ticker = createTicker(onTick);
  Duration lastTick = Duration.zero;

  void onTick(Duration elapsed) {
    if (elapsed - lastTick < const Duration(milliseconds: 33)) return;
    lastTick = elapsed;
    seconds.value = elapsed.inMicroseconds / 1000000;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool still = MediaQuery.disableAnimationsOf(context);
    if (still && ticker.isActive) ticker.stop();
    if (!still && !ticker.isActive) ticker.start();
  }

  @override
  void dispose() {
    ticker.dispose();
    seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(seconds);
}

/// Viền sáng quanh mép màn lúc AI đang làm, kiểu Siri. Không nhận chạm; hết việc thì mờ dần rồi gỡ hẳn để khỏi tốn khung hình.
class AiScreenGlow extends StatefulWidget {
  final bool active;
  final Widget child;

  const AiScreenGlow({super.key, required this.active, required this.child});

  @override
  State<AiScreenGlow> createState() => _AiScreenGlowState();
}

class _AiScreenGlowState extends State<AiScreenGlow> {
  bool visible = false;

  @override
  void initState() {
    super.initState();
    visible = widget.active;
  }

  @override
  void didUpdateWidget(AiScreenGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active) visible = true;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        widget.child,
        if (visible)
          IgnorePointer(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: widget.active ? 1 : 0),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
              onEnd: () {
                if (!widget.active && mounted) setState(() => visible = false);
              },
              builder: (BuildContext context, double opacity, Widget? child) => Opacity(opacity: opacity, child: child),
              child: RepaintBoundary(
                child: _GlowClock(
                  builder: (ValueListenable<double> seconds) => CustomPaint(painter: _ScreenGlowPainter(seconds)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ScreenGlowPainter extends CustomPainter {
  final ValueListenable<double> seconds;

  _ScreenGlowPainter(this.seconds) : super(repaint: seconds);

  @override
  void paint(Canvas canvas, Size size) {
    // Gói gốc dùng t * 0.25, rất chậm; việc của AI chỉ vài giây nên cho nhanh hơn để thấy màu chạy
    final double phase = seconds.value;
    final Rect rect = Offset.zero & size;
    final RRect rrect = RRect.fromRectAndRadius(rect, Radius.circular(math.min(size.width, size.height) * 0.14));
    final Shader shader = aiSweepGradient(phase).createShader(rect);

    void layer(double width, double blur, double opacity) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..shader = shader
          ..color = Colors.black.withValues(alpha: opacity)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
      );
    }

    // Lớp rộng nhất tốn nhất và ít thấy: máy Android chỉ vẽ hai lớp
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      layer(40, 28 + (math.sin(phase * 0.8) * 0.5 + 0.5) * 16, 0.28 + 0.1 * math.sin(phase * 0.7));
    }
    layer(20, 12, 0.5 + 0.1 * math.sin(phase * 0.9 + math.pi / 3));
    layer(14, 5, 0.85 + 0.15 * math.sin(phase * 1.1 + math.pi / 4));
  }

  @override
  bool shouldRepaint(_ScreenGlowPainter oldDelegate) => oldDelegate.seconds != seconds;
}

/// Quầng màu đổi chậm sau ô nhập hoặc nút, như AITextField. [strength] từ 0 đến 1 để quầng hiện dần.
class AiGlow extends StatelessWidget {
  final double radius;
  final bool active;
  final double strength;
  final Widget child;

  const AiGlow({super.key, required this.radius, this.active = true, this.strength = 1, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        if (active && strength > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: _GlowClock(
                  builder: (ValueListenable<double> seconds) => CustomPaint(painter: _FieldGlowPainter(seconds, radius, strength)),
                ),
              ),
            ),
          ),
        child,
      ],
    );
  }
}

class _FieldGlowPainter extends CustomPainter {
  final ValueListenable<double> seconds;
  final double radius;
  final double strength;

  _FieldGlowPainter(this.seconds, this.radius, [this.strength = 1]) : super(repaint: seconds);

  @override
  void paint(Canvas canvas, Size size) {
    final double phase = seconds.value * 0.5;
    final Rect rect = (Offset.zero & size).inflate(4);
    final double blur = 8 + (math.sin(phase * 0.8) * 0.5 + 0.5) * 8;
    final double opacity = 0.55 + 0.25 * (0.5 + 0.5 * math.sin(phase * 1.1 + math.pi / 4));
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius + 4)),
      Paint()
        ..shader = aiSweepGradient(phase).createShader(rect)
        ..color = Colors.black.withValues(alpha: opacity * strength)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
    );
  }

  @override
  bool shouldRepaint(_FieldGlowPainter oldDelegate) => oldDelegate.seconds != seconds || oldDelegate.radius != radius || oldDelegate.strength != strength;
}

/// Đổ gradient cam, hồng, xanh lên chữ hoặc biểu tượng con
class AiGradient extends StatelessWidget {
  final Widget child;

  const AiGradient({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (Rect bounds) => const LinearGradient(colors: aiTextColors).createShader(Offset.zero & bounds.size),
      child: child,
    );
  }
}

/// Logo LiftMate Intelligence: quả cầu kính có dải sáng chéo đi lên, gợi hình nâng hàng.
/// Thân cầu là kính trong suốt, thấy được nền phía sau; giao diện sáng thì kính sáng, giao diện tối thì kính tối.
/// Vẽ bằng code nên nét ở mọi cỡ, không cần file ảnh. Hình đứng yên, không tốn khung hình.
class AiOrb extends StatelessWidget {
  final double size;

  const AiOrb({super.key, this.size = 30});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(size: Size.square(size), painter: _OrbPainter(dark: AppColors.isDark)),
    );
  }
}

/// Nút tròn mở LiftMate Intelligence: cầu 44 điểm, bấm thì sáng lên và phóng to
class AiOrbButton extends StatelessWidget {
  final VoidCallback onPressed;

  const AiOrbButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: AiBrandText.brand,
      child: AiPressEffect(
        pressedScale: 1.18,
        radius: 22,
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 44),
          pressedOpacity: 1,
          onPressed: onPressed,
          child: const AiOrb(size: 44),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final bool dark;

  const _OrbPainter({required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.shortestSide;
    final double r = s / 2;
    final Offset c = size.center(Offset.zero);
    final Rect bounds = Rect.fromCircle(center: c, radius: r);
    if (dark) {
      _paintDark(canvas, s, r, c, bounds);
    } else {
      _paintLight(canvas, s, r, c, bounds);
    }
  }

  Offset _at(Offset c, double r, double x, double y) => c + Offset(x * r, y * r);

  void _fog(Canvas canvas, Offset center, double radius, Color color, BlendMode mode) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..blendMode = mode
        ..shader = RadialGradient(colors: <Color>[color, color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  // Một dải hình lá; top, bottom là điểm uốn mép trên, mép dưới, tọa độ theo bán kính cầu
  void _ribbon(Canvas canvas, Offset c, double r, Offset from, Offset to, Offset top, Offset bottom, List<Color> colors, double blur, BlendMode mode) {
    final Offset a = _at(c, r, from.dx, from.dy);
    final Offset b = _at(c, r, to.dx, to.dy);
    final Offset t = _at(c, r, top.dx, top.dy);
    final Offset d = _at(c, r, bottom.dx, bottom.dy);
    final Path path = Path()
      ..moveTo(a.dx, a.dy)
      ..quadraticBezierTo(t.dx, t.dy, b.dx, b.dy)
      ..quadraticBezierTo(d.dx, d.dy, a.dx, a.dy)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..blendMode = mode
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur)
        ..shader = LinearGradient(colors: colors).createShader(Rect.fromPoints(a, b)),
    );
  }

  // Dải sáng chéo đi lên: xanh, rồi tím hồng cam, lõi trắng ở giữa
  void _diagonalRibbons(Canvas canvas, double s, double r, Offset c, BlendMode mode) {
    _ribbon(canvas, c, r, const Offset(-1.05, 0.55), const Offset(1.05, -0.2), const Offset(-0.1, 0.1), const Offset(0.15, 0.7),
        const <Color>[Color(0xFF2F6BFF), Color(0xFF109DF7), Color(0xFF22D3EE)], s * 0.03, mode);
    _ribbon(canvas, c, r, const Offset(-0.95, 0.3), const Offset(1.05, -0.5), const Offset(0.2, -0.6), const Offset(0.05, 0.15),
        const <Color>[Color(0xFFC265F8), Color(0xFFF15D97), Color(0xFFF97A32), Color(0xFFF99911)], s * 0.028, mode);
    _ribbon(canvas, c, r, const Offset(-0.55, 0.22), const Offset(0.7, -0.28), const Offset(0.1, -0.26), const Offset(0.05, 0.1),
        const <Color>[Color(0x00FFFFFF), Color(0xFFFFFFFF), Color(0xFFFFF1D6)], s * 0.022, mode);
  }

  /// Nền sáng: kính trong, quầng sáng mềm ngoài viền, viền trắng như mép kính
  void _paintLight(Canvas canvas, double s, double r, Offset c, Rect bounds) {
    const BlendMode over = BlendMode.srcOver;
    // Chỉ vẽ quầng phía ngoài viền: thân cầu trong suốt nên không được để quầng lọt vào trong
    canvas.save();
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(bounds.inflate(s))
        ..addOval(bounds),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.09)
        ..color = Colors.black.withValues(alpha: 0.55)
        ..shader = const SweepGradient(colors: aiGlowColors).createShader(bounds),
    );
    canvas.restore();

    canvas.save();
    canvas.clipPath(Path()..addOval(bounds));
    // Kính: giữa gần như trong hẳn, về mép đục dần
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          radius: 0.5,
          colors: <Color>[Color(0x14FFFFFF), Color(0x1FFFFFFF), Color(0x73FFFFFF)],
          stops: <double>[0, 0.62, 1],
        ).createShader(bounds),
    );
    _fog(canvas, _at(c, r, -0.3, 0.4), r * 0.85, const Color(0x241F6BFF), over);
    _fog(canvas, _at(c, r, 0.35, -0.35), r * 0.75, const Color(0x1FF75E5F), over);
    _diagonalRibbons(canvas, s, r, c, over);
    // Ánh sáng phản chiếu trên đỉnh
    _fog(canvas, _at(c, r, 0, -0.62), r * 0.5, const Color(0x8CFFFFFF), over);
    canvas.drawCircle(
      c,
      r - s * 0.012,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.024
        ..color = const Color(0xB3FFFFFF),
    );
    canvas.drawCircle(
      c,
      r - s * 0.004,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.008
        ..color = const Color(0x26776FA0),
    );
    canvas.restore();
  }

  /// Nền tối: cầu kính đen, ánh sáng cộng màu, viền phát sáng
  void _paintDark(Canvas canvas, double s, double r, Offset c, Rect bounds) {
    const BlendMode plus = BlendMode.plus;
    canvas.save();
    canvas.clipPath(Path()..addOval(bounds));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.15),
          radius: 0.95,
          colors: <Color>[Color(0x661E1D33), Color(0x8C0C0C16), Color(0xBF030305)],
          stops: <double>[0, 0.6, 1],
        ).createShader(bounds),
    );
    _fog(canvas, _at(c, r, -0.3, 0.4), r * 0.85, const Color(0x8C1F6BFF), plus);
    _fog(canvas, _at(c, r, 0.35, -0.35), r * 0.75, const Color(0x80F75E5F), plus);

    _diagonalRibbons(canvas, s, r, c, plus);

    // Viền kính: cam bên phải, xanh dưới đáy, vàng nhạt bên trái, gần như trong suốt trên đỉnh
    const SweepGradient rimColors = SweepGradient(
      colors: <Color>[
        Color(0xFFF99911),
        Color(0xFF2F8BFF),
        Color(0xFF7C6BFA),
        Color(0xFFFFF1C2),
        Color(0x55FFFFFF),
        Color(0xFFF99911),
      ],
      stops: <double>[0.02, 0.27, 0.42, 0.52, 0.76, 1],
    );
    canvas.drawCircle(
      c,
      r - s * 0.03,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.06
        ..blendMode = plus
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.035)
        ..color = Colors.black.withValues(alpha: 0.75)
        ..shader = rimColors.createShader(bounds),
    );
    canvas.drawCircle(
      c,
      r - s * 0.009,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.018
        ..shader = rimColors.createShader(bounds),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OrbPainter oldDelegate) => oldDelegate.dark != dark;
}

/// Ô soạn kiểu Siri: viên thuốc màu sữa, viền trắng sáng, quầng màu phía sau, mũi tên gửi hiện khi có chữ.
/// Gõ dài thì ô giãn cao lên, biểu tượng và mũi tên nằm ở dòng cuối.
class AiPromptField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String placeholder;
  final bool enabled;
  final bool glow;
  final int? maxLength;
  final ValueChanged<String> onChanged;
  // null: chưa gửi được, mũi tên xám
  final VoidCallback? onSend;

  const AiPromptField({
    super.key,
    required this.controller,
    required this.placeholder,
    required this.onChanged,
    this.focusNode,
    this.enabled = true,
    this.glow = true,
    this.maxLength,
    this.onSend,
  });

  static const double radius = 28;

  @override
  Widget build(BuildContext context) {
    final bool hasText = controller.text.isNotEmpty;
    final Widget arrow = Icon(CupertinoIcons.arrow_up_circle, size: 30, color: onSend != null ? Colors.white : IosColors.tertiaryLabel);
    return AiGlow(
      radius: radius,
      active: glow,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        alignment: Alignment.bottomCenter,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 5, 8, 5),
          decoration: aiFieldDecoration(
            radius: radius,
            border: Border.all(color: Colors.white.withValues(alpha: AppColors.isDark ? 0.28 : 0.95), width: 1.5),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              // Cùng chiều cao với một dòng chữ. Dòng chữ, biểu tượng, mũi tên đều cao 44 nên cùng nằm giữa ô
              const Padding(
                padding: EdgeInsets.only(bottom: 10.6),
                child: AiOrb(size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                // Font hệ thống như ô nhập của Apple Intelligence.
                // Không dùng enabled: tắt ô thì Cupertino vẽ một nền xám đè lên dải màu
                child: IgnorePointer(
                  ignoring: !enabled,
                  child: CupertinoTextField(
                    controller: controller,
                    focusNode: focusNode,
                    readOnly: !enabled,
                    minLines: 1,
                    maxLines: 10,
                    maxLength: maxLength,
                    placeholder: placeholder,
                    placeholderStyle: aiTextStyle(17, fontWeight: FontWeight.w400).copyWith(height: 1.4, leadingDistribution: TextLeadingDistribution.even, color: IosColors.secondaryLabel),
                    style: aiTextStyle(17, fontWeight: FontWeight.w400).copyWith(height: 1.4, leadingDistribution: TextLeadingDistribution.even, color: AppColors.text),
                    // Chữ San Francisco nằm thấp trong dòng: nhích lên 1pt để nhìn giữa ô
                    padding: const EdgeInsets.fromLTRB(0, 9.1, 0, 11.1),
                    decoration: null,
                    onChanged: onChanged,
                  ),
                ),
              ),
              Visibility(
                visible: hasText,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  onPressed: onSend,
                  child: onSend != null ? AiGradient(child: arrow) : arrow,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Câu có tên LiftMate Intelligence: riêng tên đổ dải màu, phần còn lại màu chữ thường
class AiBrandText extends StatelessWidget {
  static const String brand = 'LiftMate Intelligence';

  final String text;
  final double fontSize;

  const AiBrandText(this.text, {super.key, this.fontSize = 17});

  @override
  Widget build(BuildContext context) {
    final TextStyle style = aiTextStyle(fontSize, fontWeight: FontWeight.w400).copyWith(color: AppColors.text);
    final int start = text.indexOf(brand);
    if (start < 0) return Text(text, style: style);
    return Text.rich(
      TextSpan(
        style: style,
        children: <InlineSpan>[
          TextSpan(text: text.substring(0, start)),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: AiGradient(child: Text(brand, style: aiTextStyle(fontSize, fontWeight: FontWeight.w600))),
          ),
          TextSpan(text: text.substring(start + brand.length)),
        ],
      ),
    );
  }
}

class _SlideGradient extends GradientTransform {
  final double fraction;

  const _SlideGradient(this.fraction);

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * fraction, 0, 0);
  }
}

/// Bấm vào thì phóng to có nảy và sáng lên, thả ra về cỡ cũ, như nút kính gốc của iOS.
/// Đứng yên không chạy đồng hồ. [enabled] tắt thì không có hiệu ứng.
class AiPressEffect extends StatefulWidget {
  static const SpringDescription spring = SpringDescription(mass: 1, stiffness: 420, damping: 20);

  final double pressedScale;
  final double radius;
  final bool enabled;
  final Widget child;

  const AiPressEffect({super.key, required this.pressedScale, required this.radius, this.enabled = true, required this.child});

  @override
  State<AiPressEffect> createState() => _AiPressEffectState();
}

class _AiPressEffectState extends State<AiPressEffect> with TickerProviderStateMixin {
  late final AnimationController scale = AnimationController.unbounded(vsync: this, value: 1);
  late final AnimationController light = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 110),
    reverseDuration: const Duration(milliseconds: 320),
  );
  int pointers = 0;

  void press() {
    if (!widget.enabled) return;
    pointers++;
    if (pointers > 1) return;
    scale.animateWith(SpringSimulation(AiPressEffect.spring, scale.value, widget.pressedScale, scale.velocity));
    light.forward();
  }

  void release() {
    if (pointers == 0) return;
    pointers--;
    if (pointers > 0) return;
    scale.animateWith(SpringSimulation(AiPressEffect.spring, scale.value, 1, scale.velocity));
    light.reverse();
  }

  @override
  void didUpdateWidget(AiPressEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && pointers > 0) {
      pointers = 1;
      release();
    }
  }

  @override
  void dispose() {
    scale.dispose();
    light.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (PointerDownEvent event) => press(),
      onPointerUp: (PointerUpEvent event) => release(),
      onPointerCancel: (PointerCancelEvent event) => release(),
      child: ScaleTransition(
        scale: scale,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned.fill(
              child: IgnorePointer(
                child: FadeTransition(
                  opacity: light,
                  child: CustomPaint(painter: _PressGlowPainter(widget.radius)),
                ),
              ),
            ),
            widget.child,
            // Lớp sáng phủ lên trên, rõ nhất ở nền tối
            Positioned.fill(
              child: IgnorePointer(
                child: FadeTransition(
                  opacity: light,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(widget.radius),
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PressGlowPainter extends CustomPainter {
  final double radius;

  const _PressGlowPainter(this.radius);

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.inflate(3), Radius.circular(radius + 3)),
      Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12)
        ..color = Colors.black.withValues(alpha: 0.85)
        ..shader = const SweepGradient(colors: aiGlowColors).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_PressGlowPainter oldDelegate) => oldDelegate.radius != radius;
}

/// Nút trong khu vực LiftMate Intelligence: nền pha nhạt dải màu, viền và chữ cùng dải màu như ảnh mẫu.
/// [halo] thêm quầng sáng nhẹ cho nút chính. Hình đứng yên nên không tốn khung hình.
class AiButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool halo;
  final VoidCallback? onPressed;

  const AiButton({super.key, required this.label, this.icon, this.halo = true, required this.onPressed});

  static const double height = 52;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    final Color disabledColor = IosColors.tertiaryLabel;
    final Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, color: enabled ? Colors.white : disabledColor, size: 20),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: aiTextStyle(17).copyWith(color: enabled ? Colors.white : disabledColor),
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      enabled: enabled,
      child: AiPressEffect(
        pressedScale: 1.05,
        radius: height / 2,
        enabled: enabled,
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, height),
          pressedOpacity: 1,
          onPressed: onPressed,
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: CustomPaint(
              painter: _AiButtonPainter(enabled: enabled, halo: halo, fill: AppColors.surface, disabledBorder: IosColors.separator),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(child: enabled ? AiGradient(child: content) : content),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AiButtonPainter extends CustomPainter {
  final bool enabled;
  final bool halo;
  final Color fill;
  final Color disabledBorder;

  const _AiButtonPainter({required this.enabled, required this.halo, required this.fill, required this.disabledBorder});

  static const double borderWidth = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final RRect pill = RRect.fromRectAndRadius(rect, Radius.circular(size.height / 2));
    final Shader colors = const LinearGradient(colors: aiTextColors).createShader(rect);
    if (enabled && halo) {
      canvas.drawRRect(
        pill,
        Paint()
          ..shader = colors
          ..color = Colors.black.withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
      );
    }
    canvas.drawRRect(pill, Paint()..color = fill);
    if (enabled) {
      canvas.drawRRect(
        pill,
        Paint()
          ..shader = colors
          ..color = Colors.black.withValues(alpha: aiTintOpacity),
      );
    }
    final Paint border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;
    if (enabled) {
      border.shader = colors;
    } else {
      border.color = disabledBorder;
    }
    canvas.drawRRect(pill.deflate(borderWidth / 2), border);
  }

  @override
  bool shouldRepaint(_AiButtonPainter oldDelegate) {
    return oldDelegate.enabled != enabled || oldDelegate.halo != halo || oldDelegate.fill != fill || oldDelegate.disabledBorder != disabledBorder;
  }
}

/// Chữ có vệt sáng chạy qua, báo đang chờ AI (textGlow)
class AiShimmerText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final TextAlign textAlign;

  const AiShimmerText(this.text, {super.key, required this.style, this.textAlign = TextAlign.start});

  @override
  State<AiShimmerText> createState() => _AiShimmerTextState();
}

class _AiShimmerTextState extends State<AiShimmerText> with SingleTickerProviderStateMixin {
  late final AnimationController loop = AnimationController(vsync: this, duration: const Duration(seconds: 2));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      loop.stop();
    } else if (!loop.isAnimating) {
      loop.repeat();
    }
  }

  @override
  void dispose() {
    loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color strong = AppColors.text.withValues(alpha: 0.85);
    final Color faint = AppColors.text.withValues(alpha: 0.22);
    return AnimatedBuilder(
      animation: loop,
      child: Text(widget.text, textAlign: widget.textAlign, style: widget.style.copyWith(color: Colors.white)),
      builder: (BuildContext context, Widget? child) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (Rect bounds) => LinearGradient(
          colors: <Color>[strong, strong, faint, strong, strong],
          stops: const <double>[0, 0.3, 0.5, 0.7, 1],
          tileMode: TileMode.repeated,
          transform: _SlideGradient(loop.value),
        ).createShader(Offset.zero & bounds.size),
        child: child,
      ),
    );
  }
}

/// Các dòng xám chờ chữ, có dải cầu vồng chạy từ dưới lên (AIGeneratingText)
class AiGeneratingLines extends StatefulWidget {
  final int lineCount;

  const AiGeneratingLines({super.key, this.lineCount = 5});

  @override
  State<AiGeneratingLines> createState() => _AiGeneratingLinesState();
}

class _AiGeneratingLinesState extends State<AiGeneratingLines> with SingleTickerProviderStateMixin {
  late final AnimationController loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      loop.stop();
    } else if (!loop.isAnimating) {
      loop.repeat();
    }
  }

  @override
  void dispose() {
    loop.dispose();
    super.dispose();
  }

  static const double lineHeight = 15;
  static const double lineSpacing = 8;

  @override
  Widget build(BuildContext context) {
    final double height = widget.lineCount * lineHeight + (widget.lineCount - 1) * lineSpacing;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _GeneratingLinesPainter(loop, widget.lineCount, IosColors.tertiaryLabel.withValues(alpha: 0.25))),
    );
  }
}

class _GeneratingLinesPainter extends CustomPainter {
  final Animation<double> progress;
  final int lineCount;
  final Color placeholder;

  _GeneratingLinesPainter(this.progress, this.lineCount, this.placeholder) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    final Path lines = Path();
    for (int i = 0; i < lineCount; i++) {
      // Dòng cuối ngắn hơn, trông như đoạn văn thật
      final double width = i == lineCount - 1 && lineCount > 1 ? size.width * 0.6 : size.width;
      final double top = i * (_AiGeneratingLinesState.lineHeight + _AiGeneratingLinesState.lineSpacing);
      lines.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, top, width, _AiGeneratingLinesState.lineHeight), const Radius.circular(4)));
    }
    canvas.drawPath(lines, Paint()..color = placeholder);

    final double offset = (1 - 2 * progress.value) * size.height;
    final Rect band = Rect.fromLTWH(0, offset, size.width, size.height);
    canvas.drawPath(
      lines,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: <Color>[
            Color(0x00FF3B30),
            Color(0x99FF3B30),
            Color(0x99FF9500),
            Color(0x99FFCC00),
            Color(0x9934C759),
            Color(0x99007AFF),
            Color(0x995856D6),
            Color(0x99AF52DE),
            Color(0x00AF52DE),
          ],
        ).createShader(band),
    );
  }

  @override
  bool shouldRepaint(_GeneratingLinesPainter oldDelegate) => false;
}

/// Chữ, thẻ AI vừa làm xong nhảy lên và giãn nhẹ một lần (đoạn cuối của AIGeneratingText)
class AiReveal extends StatefulWidget {
  final Duration delay;
  final bool animate;
  final Widget child;

  const AiReveal({super.key, this.delay = Duration.zero, this.animate = true, required this.child});

  @override
  State<AiReveal> createState() => _AiRevealState();
}

class _AiRevealState extends State<AiReveal> with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 480));
  Timer? delay;

  @override
  void initState() {
    super.initState();
    if (!widget.animate) {
      controller.value = 1;
    } else if (widget.delay == Duration.zero) {
      controller.forward();
    } else {
      delay = Timer(widget.delay, () {
        if (mounted) controller.forward();
      });
    }
  }

  @override
  void dispose() {
    delay?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        final double value = controller.value;
        if (value == 1) return child!;
        final double jump = Curves.easeOutBack.transform(value);
        return Opacity(
          opacity: Curves.easeOut.transform(math.min(1, value * 2.5)),
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - jump)),
            child: Transform(
              alignment: Alignment.topCenter,
              transform: Matrix4.diagonal3Values(1, 1 + 0.08 * math.sin(value * math.pi), 1),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
