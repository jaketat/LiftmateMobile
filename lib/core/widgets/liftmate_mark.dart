import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme.dart';

// Tag để logo và chữ bay từ màn khởi động sang màn đăng nhập
const String markHeroTag = 'liftmate-mark';
const String wordHeroTag = 'liftmate-word';

// Màu navy của logo trên web (hơi khác AppColors.navy)
const Color logoNavy = Color(0xFF0B2451);

// Đường cong "vượt đà rồi nảy về" của web
const Cubic overshootCurve = Cubic(0.34, 1.56, 0.64, 1);
const Cubic softOutCurve = Cubic(0.22, 1, 0.36, 1);

// Tiến độ 0–1 của một đoạn chuyển động, tính theo giây. Mốc thời gian = web × 0,75 cho nhanh hơn
double motionPhase(double seconds, double start, double duration, [Curve curve = Curves.linear]) {
  final double raw = ((seconds - start) / duration).clamp(0.0, 1.0);
  return curve.transform(raw);
}

// Logo LiftMate đứng yên, tỉ lệ khung 192 × 380. Icon app được xuất từ chính hình này
class LiftMateMark extends StatelessWidget {
  const LiftMateMark({super.key, required this.height, this.primary = logoNavy, this.hole = Colors.white});

  final double height;
  final Color primary;
  final Color hole;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(height * 192 / 380, height),
      painter: LiftMateMarkPainter(primary: primary, hole: hole),
    );
  }
}

// Chữ LiftMate: "Lift" navy, "Mate" cam. Có đồng hồ thì từng ký tự nảy lên lần lượt.
// FittedBox để chữ đang bay giữa 2 cỡ không bị tràn hay xuống dòng
class LiftMateWord extends StatelessWidget {
  const LiftMateWord({super.key, required this.fontSize, this.clock});

  final double fontSize;
  final Animation<double>? clock;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = GoogleFonts.nunito(
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      height: 1.05,
      letterSpacing: fontSize * -0.01,
      // Lúc bay, Hero nằm ngoài Scaffold: không ghi rõ thì Flutter gạch chân chữ màu vàng
      decoration: TextDecoration.none,
    );
    const String word = 'LiftMate';
    return Semantics(
      label: word,
      child: ExcludeSemantics(
        child: FittedBox(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int index = 0; index < word.length; index++)
                letter(word[index], index, style.copyWith(color: index < 4 ? logoNavy : AppColors.orange)),
            ],
          ),
        ),
      ),
    );
  }

  Widget letter(String character, int index, TextStyle style) {
    final Animation<double>? ticking = clock;
    if (ticking == null) {
      return Text(character, style: style);
    }
    return AnimatedBuilder(
      animation: ticking,
      builder: (BuildContext context, Widget? child) {
        final double shown = motionPhase(ticking.value, 1.09 + index * 0.045, 0.49, overshootCurve);
        return Transform.translate(
          offset: Offset(0, fontSize * 0.6 * (1 - shown)),
          child: Opacity(opacity: shown.clamp(0.0, 1.0), child: child),
        );
      },
      child: Text(character, style: style),
    );
  }
}

// Các chấm màu trôi nhẹ trên nền trắng, như đầu trang web.
// startAt: mở màn đăng nhập ở đúng nhịp màn khởi động đang chạy, chấm không bị giật về chỗ cũ
class LiftMateSparks extends StatefulWidget {
  const LiftMateSparks({super.key, this.startAt = 0});

  final double startAt;

  @override
  State<LiftMateSparks> createState() {
    return _LiftMateSparksState();
  }
}

class _LiftMateSparksState extends State<LiftMateSparks> with SingleTickerProviderStateMixin {
  late final AnimationController clock = AnimationController(
    vsync: this,
    upperBound: 3600,
    value: widget.startAt,
    duration: const Duration(hours: 1),
  );
  bool started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (started) {
      return;
    }
    started = true;
    // Máy tắt hiệu ứng thì chấm đứng yên
    if (!MediaQuery.disableAnimationsOf(context)) {
      clock.forward();
    }
  }

  @override
  void dispose() {
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary (Flutter): chấm màu vẽ lại không kéo theo cả màn
    return RepaintBoundary(
      child: CustomPaint(size: Size.infinite, painter: _SparksPainter(clock)),
    );
  }
}

// Một chấm màu nền: vị trí theo tỉ lệ màn, cỡ, màu, thời gian trôi (lấy từ .sparks của web)
class _Spark {
  const _Spark(this.x, this.y, this.size, this.color, this.seconds);

  final double x;
  final double y;
  final double size;
  final Color color;
  final double seconds;
}

class _SparksPainter extends CustomPainter {
  _SparksPainter(this.clock) : super(repaint: clock);

  final Animation<double> clock;

  static const List<_Spark> sparks = <_Spark>[
    _Spark(0.08, 0.22, 14, AppColors.orange, 9),
    _Spark(0.18, 0.62, 10, Color(0xFF3D8BFF), 11),
    _Spark(0.30, 0.08, 7, Color(0xFFFF4F8B), 8),
    _Spark(0.72, 0.12, 12, Color(0xFF2AC8E8), 12),
    _Spark(0.86, 0.40, 8, AppColors.orange, 10),
    _Spark(0.92, 0.75, 10, Color(0xFFA45CFF), 13),
    _Spark(0.64, 0.58, 6, Color(0xFFFF8A3C), 7),
    _Spark(0.40, 0.80, 9, Color(0xFF3D8BFF), 14),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final _Spark spark in sparks) {
      // Trôi qua 3 mốc (0,0) → (18,-26) → (-14,12) rồi đi ngược lại
      final double round = clock.value / spark.seconds;
      final double swing = 1 - (round % 2 - 1).abs();
      final double eased = Curves.easeInOut.transform(swing);
      final Offset drift = eased < 0.5
          ? Offset.lerp(Offset.zero, const Offset(18, -26), eased * 2)!
          : Offset.lerp(const Offset(18, -26), const Offset(-14, 12), eased * 2 - 1)!;
      final Paint paint = Paint()
        ..color = spark.color.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);
      canvas.drawCircle(
        Offset(size.width * spark.x, size.height * spark.y) + drift,
        spark.size / 2,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SparksPainter oldDelegate) {
    return oldDelegate.clock != clock;
  }
}

// Logo LiftMate, chép từ SVG trên web (khung 192 × 380, gốc tại 104, -34).
// Vẽ tay để từng phần chuyển động riêng: móc cẩu, dây, hai người, vòng ôm, mũi tên.
class LiftMateMarkPainter extends CustomPainter {
  LiftMateMarkPainter({this.clock, this.primary = logoNavy, this.hole = Colors.white, this.settle = 0})
      : super(repaint: clock);

  // Đồng hồ tính bằng giây. Không truyền thì vẽ logo đã lắp xong, đứng yên
  final Animation<double>? clock;
  // Màu người bên trái và móc cẩu; đổi sang trắng khi đặt trên nền tối
  final Color primary;
  // Màu lỗ tròn trên khối móc: trùng màu nền
  final Color hole;
  // 0 = đung đưa đủ, 1 = đứng yên hẳn (lúc logo đang bay)
  final double settle;

  static final Path hookBlock = Path()
    ..moveTo(176, 34)
    ..lineTo(224, 34)
    ..lineTo(236, 60)
    ..lineTo(216, 94)
    ..lineTo(184, 94)
    ..lineTo(164, 60)
    ..close();
  static final Path hookCurve = Path()
    ..moveTo(200, 100)
    ..cubicTo(200, 112, 182, 114, 182, 130)
    ..cubicTo(182, 146, 206, 150, 214, 136);
  static final Path hookTip = Path()
    ..moveTo(214, 136)
    ..cubicTo(218, 128, 226, 126, 228, 118);
  static final Path bodyLeft = Path()
    ..moveTo(152, 214)
    ..lineTo(160, 266)
    ..moveTo(160, 266)
    ..lineTo(124, 336)
    ..moveTo(160, 266)
    ..lineTo(186, 338)
    ..moveTo(156, 220)
    ..lineTo(198, 248);
  static final Path bodyRight = Path()
    ..moveTo(248, 214)
    ..lineTo(240, 266)
    ..moveTo(240, 266)
    ..lineTo(276, 336)
    ..moveTo(240, 266)
    ..lineTo(214, 338)
    ..moveTo(244, 220)
    ..lineTo(202, 248);
  static final Path bowl = Path()
    ..moveTo(162, 242)
    ..cubicTo(174, 280, 226, 282, 240, 246)
    ..cubicTo(222, 266, 180, 266, 162, 242)
    ..close();
  static final Path arrow = Path()
    ..moveTo(176, 266)
    ..cubicTo(198, 274, 222, 262, 236, 240);
  static final Path arrowTip = Path()
    ..moveTo(249, 222)
    ..lineTo(225, 231)
    ..lineTo(243, 250)
    ..close();

  Paint fill(Color color, double opacity) {
    return Paint()..color = color.withValues(alpha: opacity);
  }

  Paint stroke(Color color, double width, double opacity) {
    return Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
  }

  // Phóng to từ 0 quanh một điểm (kiểu "bật ra")
  void popAround(Canvas canvas, Offset center, double scale) {
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.translate(-center.dx, -center.dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double seconds = clock?.value ?? 10;
    final double unit = size.width / 192;
    canvas.scale(unit);
    canvas.translate(-104, 34);

    drawHook(canvas, seconds);

    // Sau khi lắp xong, hai người và mũi tên nhấp nhô nhẹ như đang nâng
    final double heave = clock == null || seconds < 1.35 ? 0 : -5 * (1 - math.cos((seconds - 1.35) * math.pi / 2.6)) / 2 * (1 - settle);

    final double walkIn = motionPhase(seconds, 0.45, 0.6, softOutCurve);
    canvas.save();
    canvas.translate(-80 * (1 - walkIn), heave);
    canvas.drawCircle(const Offset(150, 180), 21, fill(primary, walkIn));
    canvas.drawPath(bodyLeft, stroke(primary, 23, walkIn));
    canvas.restore();

    canvas.save();
    canvas.translate(80 * (1 - walkIn), heave);
    canvas.drawCircle(const Offset(250, 180), 21, fill(AppColors.orange, walkIn));
    canvas.drawPath(bodyRight, stroke(AppColors.orange, 23, walkIn));
    canvas.restore();

    canvas.save();
    canvas.translate(0, heave);

    final double bowlPop = motionPhase(seconds, 0.975, 0.45, overshootCurve);
    if (bowlPop > 0) {
      canvas.save();
      popAround(canvas, const Offset(201, 251), bowlPop);
      canvas.drawPath(bowl, fill(AppColors.orange, 1));
      canvas.restore();
    }

    final double arrowDraw = motionPhase(seconds, 1.16, 0.45, Curves.easeOut);
    if (arrowDraw > 0) {
      final PathMetric metric = arrow.computeMetrics().first;
      canvas.drawPath(metric.extractPath(0, metric.length * arrowDraw), stroke(primary, 8, 1));
    }

    final double tipPop = motionPhase(seconds, 1.54, 0.34, overshootCurve);
    if (tipPop > 0) {
      popAround(canvas, const Offset(234.6, 238.8), tipPop);
      canvas.drawPath(arrowTip, fill(primary, 1));
    }
    canvas.restore();
  }

  // Móc cẩu: thả từ trên xuống, nảy nhẹ, sau đó đung đưa quanh đỉnh dây
  void drawHook(Canvas canvas, double seconds) {
    final double drop = motionPhase(seconds, 0.075, 0.825, overshootCurve);
    final double opacity = drop.clamp(0.0, 1.0);
    if (opacity == 0) {
      return;
    }
    canvas.save();
    canvas.translate(0, -140 * (1 - drop));
    final double sway = clock == null || seconds < 0.975 ? 0 : math.sin((seconds - 0.975) * math.pi / 4.5) * 2 * math.pi / 180 * (1 - settle);
    canvas.translate(200, -34);
    canvas.rotate(sway);
    canvas.translate(-200, 34);

    final Paint navyFill = fill(primary, opacity);
    canvas.drawRRect(RRect.fromLTRBR(185, -34, 194, 36, const Radius.circular(3)), navyFill);
    canvas.drawRRect(RRect.fromLTRBR(206, -34, 215, 36, const Radius.circular(3)), navyFill);
    canvas.drawPath(hookBlock, navyFill);
    canvas.drawCircle(const Offset(200, 60), 9, fill(hole, opacity));
    canvas.drawCircle(const Offset(200, 60), 3.8, navyFill);
    canvas.drawRRect(RRect.fromLTRBR(195, 92, 205, 102, const Radius.circular(2)), navyFill);
    canvas.drawPath(hookCurve, stroke(primary, 10, opacity));
    canvas.drawPath(hookTip, stroke(primary, 7, opacity));

    // Hai sợi dây cáp tự kéo dài ra khi móc đã xuống gần hết
    final double sling = motionPhase(seconds, 0.71, 0.375, Curves.easeOut);
    if (sling > 0) {
      canvas.drawLine(
        const Offset(194, 147),
        Offset.lerp(const Offset(194, 147), const Offset(172, 206), sling)!,
        stroke(primary, 7, opacity),
      );
      canvas.drawLine(
        const Offset(206, 147),
        Offset.lerp(const Offset(206, 147), const Offset(228, 206), sling)!,
        stroke(AppColors.orange, 7, opacity),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(LiftMateMarkPainter oldDelegate) {
    return oldDelegate.clock != clock || oldDelegate.primary != primary || oldDelegate.hole != hole || oldDelegate.settle != settle;
  }
}
