// Khối "kính mờ" kiểu Apple Liquid Glass: làm mờ nền phía sau, phủ trắng trong,
// viền sáng mảnh, bóng đổ mềm. Dùng cho app tài xế nổi trên bản đồ (canvas trang "Tài xế").
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Android: bỏ làm mờ nền (GPU tầm trung không gánh nổi nhiều lớp mờ trên bản đồ), thay bằng nền gần đục.
/// Riêng thanh tab vẫn giữ kính thật vì chỉ tốn một lớp nhỏ.
bool get glassBlurEnabled => defaultTargetPlatform != TargetPlatform.android;

/// iOS: dùng control native của gói cupertino_native. Android giữ bản Flutter, vì bản thay thế của gói trên Android
/// vẽ mọi icon tab thành cùng một hình tròn.
bool get useNativeControls => defaultTargetPlatform == TargetPlatform.iOS;

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
        ..color = const Color(0x24101828),
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
          colors: <Color>[
            Colors.white,
            Colors.white.withValues(alpha: 0.55),
            Colors.white.withValues(alpha: 0.25),
            Colors.white.withValues(alpha: 0.6),
            Colors.white.withValues(alpha: 0.95),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(GlassRimPainter oldDelegate) => oldDelegate.borderRadius != borderRadius;
}

class Glass extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  // Độ đục của lớp trắng (0.5–0.8). Cao hơn khi chữ cần đọc rõ trên nền bản đồ rối.
  final double opacity;
  final double blur;
  final bool shadow;

  const Glass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.padding,
    this.opacity = 0.6,
    this.blur = 26,
    this.shadow = true,
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
    if (!glassBlurEnabled) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          color: Colors.white.withValues(alpha: (0.7 + opacity * 0.3).clamp(0.0, 1.0)),
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
    // Liquid Glass: lớp trắng rất mỏng (khoảng một nửa [opacity] cũ) để thấy rõ nền phía sau,
    // bù lại bằng làm mờ mạnh + tăng màu, viền sáng mảnh và vệt bóng ở mép trên.
    // Trong hơn nữa: lớp trắng chỉ còn khoảng 1/3 [opacity] cũ, làm nhòe nhẹ hơn để thấy rõ hình phía sau
    final double base = (opacity * 0.32).clamp(0.0, 1.0);
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
          filter: ImageFilter.compose(
            outer: _saturate,
            inner: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          ),
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

  const GlassCircleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 52,
    this.color = AppColors.navy,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
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
        decoration: BoxDecoration(color: const Color(0x38101828), borderRadius: BorderRadius.circular(99)),
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

  const GlassTabBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.compact = false,
    // Navy của LiftMate cho tab đang chọn
    this.accent = AppColors.navy,
  });

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
          final Color color = on ? widget.accent : const Color(0xFF000000);
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
          filter: ImageFilter.compose(
            outer: Glass._saturate,
            inner: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          ),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              borderRadius: radius,
              color: Colors.white.withValues(alpha: tabBarFillOpacity),
              // Đường tối rất mảnh ở mép, giữ được hình thanh khi nền phía sau cũng trắng
              border: Border.all(color: Colors.black.withValues(alpha: 0.12), width: 0.5),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}
