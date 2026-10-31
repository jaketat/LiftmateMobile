// Nút "vuốt để xác nhận" kiểu Grab, phong cách Liquid Glass:
// - Thanh trượt là kính trong (làm mờ bản đồ phía sau, phủ navy trong suốt, viền sáng, vệt bóng phía trên).
// - Chữ có vệt sáng chạy ngang liên tục như "slide to unlock" của iPhone.
// - Núm là viên kính trắng; phần đã kéo qua sáng dần lên.
// Kéo núm sang phải hết cỡ mới gửi mốc, tránh chạm nhầm khi điện thoại để trên giá đỡ.
// Trình đọc màn hình: bấm đúp để xác nhận.
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../core/widgets/glass.dart' show GlassRimPainter, glassBlurEnabled;

class SlideToConfirm extends StatefulWidget {
  final String label;
  final Future<void> Function() onConfirmed;
  final bool enabled;
  final Color color;

  const SlideToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.enabled = true,
    this.color = AppColors.navy,
  });

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm> with TickerProviderStateMixin {
  static const double height = 66;
  static const double knob = 58;
  static const double inset = 4;

  double offset = 0;
  bool busy = false;
  bool dragging = false;

  // Vệt sáng chạy qua chữ: vài lượt rồi dừng (lặp mãi thì màn hình phải vẽ lại liên tục, nóng máy), 2,2 giây một lượt
  static const int shineRuns = 3;
  late final AnimationController shine =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(count: shineRuns);
  // Núm trượt về chỗ cũ khi buông tay chưa tới đích
  late final AnimationController back = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  Animation<double>? backAnimation;

  @override
  void dispose() {
    shine.dispose();
    back.dispose();
    super.dispose();
  }

  void _springBack() {
    backAnimation = Tween<double>(begin: offset, end: 0)
        .animate(CurvedAnimation(parent: back, curve: Curves.easeOutBack))
      ..addListener(() {
        setState(() {
          offset = backAnimation!.value.clamp(0.0, double.infinity);
        });
      });
    back.forward(from: 0);
    // Buông tay chưa xác nhận: nhắc lại một lượt vệt sáng
    shine.forward(from: 0);
  }

  Future<void> _confirm() async {
    if (busy || !widget.enabled) {
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      busy = true;
    });
    try {
      await widget.onConfirmed();
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
        _springBack();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color tint = widget.enabled ? widget.color : AppColors.textMuted;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double maxOffset = constraints.maxWidth - knob - inset * 2;
        final double progress = maxOffset <= 0 ? 0 : (offset / maxOffset).clamp(0.0, 1.0);
        final BorderRadius radius = BorderRadius.circular(999);

        // Thanh kính
        final Widget face = Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: radius,
            // Navy trong suốt, đậm dần khi kéo
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                // Kính xám trung tính như "slide to answer" của iPhone
                const Color(0xFFF2F2F7).withValues(alpha: glassBlurEnabled ? 0.30 + progress * 0.15 : 0.92),
                const Color(0xFFD1D1D6).withValues(alpha: glassBlurEnabled ? 0.38 + progress * 0.15 : 0.92),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 0.8),
          ),
          child: Stack(
            children: <Widget>[
              // Vệt bóng cong ở nửa trên, như mặt kính lồi
              Positioned(
                left: 10,
                right: 10,
                top: 2,
                height: height * 0.42,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Colors.white.withValues(alpha: 0.35),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              // Phần đã kéo qua: sáng lên theo núm
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: inset + offset + knob,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    color: Colors.white.withValues(alpha: progress * 0.10),
                  ),
                ),
              ),
              // Chữ có vệt sáng chạy
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.only(left: knob + inset + 6, right: 20),
                  child: Center(
                    child: Opacity(
                      opacity: (1 - progress * 1.4).clamp(0.0, 1.0),
                      child: busy
                          ? Text(
                              t('common.sending'),
                              style: const TextStyle(color: Color(0xFF2C2C2E), fontSize: 18, fontWeight: FontWeight.w400),
                            )
                          : _ShimmerText(
                              text: widget.label,
                              animation: shine,
                              running: widget.enabled && !dragging,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
        final Widget track = ClipRRect(
          borderRadius: radius,
          child: glassBlurEnabled
              ? BackdropFilter(filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), child: face)
              : CustomPaint(foregroundPainter: GlassRimPainter(radius), child: face),
        );

        // Núm kính trắng
        final Widget thumb = AnimatedScale(
          scale: dragging ? 1.06 : 1,
          duration: const Duration(milliseconds: 140),
          child: Container(
            width: knob,
            height: knob,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: <BoxShadow>[
                BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 3)),
              ],
            ),
            child: busy
                ? Padding(
                    padding: const EdgeInsets.all(15),
                    child: CupertinoActivityIndicator(color: tint),
                  )
                : Icon(Icons.arrow_forward_rounded, color: tint, size: 28),
          ),
        );

        return Semantics(
          button: true,
          enabled: widget.enabled && !busy,
          label: t('slide.semantics', <String, Object?>{'action': widget.label}),
          onTap: _confirm,
          excludeSemantics: true,
          child: DecoratedBox(
            // Bóng mềm dưới thanh kính
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: <BoxShadow>[
                BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 20, offset: const Offset(0, 6)),
              ],
            ),
            child: SizedBox(
              height: height,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(child: track),
                  Positioned(
                    left: inset + offset,
                    top: (height - knob) / 2,
                    child: GestureDetector(
                      onHorizontalDragStart: (!widget.enabled || busy)
                          ? null
                          : (DragStartDetails _) {
                              back.stop();
                              setState(() => dragging = true);
                            },
                      onHorizontalDragUpdate: (!widget.enabled || busy)
                          ? null
                          : (DragUpdateDetails details) {
                              setState(() {
                                offset = (offset + details.delta.dx).clamp(0.0, maxOffset);
                              });
                            },
                      onHorizontalDragEnd: (!widget.enabled || busy)
                          ? null
                          : (DragEndDetails details) {
                              setState(() => dragging = false);
                              if (offset >= maxOffset * 0.85) {
                                setState(() {
                                  offset = maxOffset;
                                });
                                _confirm();
                              } else {
                                _springBack();
                              }
                            },
                      child: thumb,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Chữ trắng mờ có một vệt sáng chạy từ trái sang phải (giống "slide to unlock").
class _ShimmerText extends StatelessWidget {
  final String text;
  final Animation<double> animation;
  final bool running;

  const _ShimmerText({required this.text, required this.animation, required this.running});

  @override
  Widget build(BuildContext context) {
    // Chữ mảnh như iOS; màu thật do ShaderMask quyết (xám đậm + vệt sáng trắng)
    const TextStyle style = TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w400, letterSpacing: 0.1);
    final Widget label = Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    if (!running) {
      return DefaultTextStyle.merge(
        style: const TextStyle(color: Color(0xFF6C6C70)),
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style.copyWith(color: const Color(0xFF6C6C70))),
      );
    }
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        // Vệt sáng đi từ ngoài mép trái (-1) tới ngoài mép phải (2)
        final double x = -1.0 + animation.value * 3.0;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (Rect bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: <Color>[
                const Color(0xFF6C6C70),
                const Color(0xFF6C6C70),
                Colors.white,
                const Color(0xFF6C6C70),
                const Color(0xFF6C6C70),
              ],
              stops: <double>[
                0.0,
                (x - 0.12).clamp(0.0, 1.0),
                x.clamp(0.0, 1.0),
                (x + 0.12).clamp(0.0, 1.0),
                1.0,
              ],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: label,
    );
  }
}
