// Nút "vuốt để xác nhận" kiểu Grab, phong cách Liquid Glass:
// - Thanh trượt là kính trắng trong, làm mờ bản đồ phía sau, viền sáng và bóng mềm.
// - Chữ có dải nhạt trôi mượt liên tục qua dòng chữ.
// - Núm màu chính, mũi tên trắng; phần đã kéo qua đậm dần theo màu núm.
// Kéo núm sang phải hết cỡ mới gửi mốc, tránh chạm nhầm khi điện thoại để trên giá đỡ.
// Trình đọc màn hình: bấm đúp để xác nhận.
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../core/i18n.dart';

/// Lớp trắng phủ trên kính của thanh trượt: càng thấp càng trong. Là số ước lượng theo mắt.
const double trackFillOpacity = 0.4;

/// Một lượt dải nhạt chạy qua chữ, chạy đều không nhanh dần. Là số ước lượng theo mắt, đổi ở đây nếu thấy nhanh hay chậm.
const Duration shineDuration = Duration(milliseconds: 2000);

/// Nửa chiều dài dải nhạt, tính theo chiều rộng chữ: cả dải dài bằng hơn nửa dòng chữ
const double shineHalfLength = 0.3;

/// Màu chữ thường, và màu nhạt nhất ở giữa dải
const Color shineBaseColor = Color(0xFF3A3A3C);
const Color shinePeakColor = Color(0xFFC7C7CC);

// Vị trí các mốc trong dải (-1 mép trái, 0 giữa, 1 mép phải) và độ nhạt tại đó theo đường cong cosin:
// màu đổi dần từ mép vào giữa nên không thấy mép cứng.
const List<double> _shineOffsets = <double>[-1, -0.75, -0.5, -0.25, 0, 0.25, 0.5, 0.75, 1];
const List<double> _shineWeights = <double>[0, 0.146, 0.5, 0.854, 1, 0.854, 0.5, 0.146, 0];

/// Màu của dải, kèm hai đầu là màu chữ thường cho phần ngoài dải
final List<Color> shineColors = <Color>[
  shineBaseColor,
  for (final double weight in _shineWeights) Color.lerp(shineBaseColor, shinePeakColor, weight)!,
  shineBaseColor,
];

/// Các mốc màu tại [value] (0–1): dải vào từ ngoài mép trái, ra hết ngoài mép phải rồi lặp, không có khoảng chết.
List<double> shineStops(double value) {
  final double center = -shineHalfLength + value * (1 + shineHalfLength * 2);
  return <double>[
    0.0,
    for (final double offset in _shineOffsets) (center + offset * shineHalfLength).clamp(0.0, 1.0),
    1.0,
  ];
}

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

  // Vệt sáng chạy qua chữ như "slide to unlock": luôn lặp đều, chỉ dừng khi đang gửi hoặc bị khóa
  late final AnimationController shine = AnimationController(vsync: this, duration: shineDuration);

  @override
  void initState() {
    super.initState();
    _updateShine();
  }

  @override
  void didUpdateWidget(covariant SlideToConfirm oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateShine();
  }

  void _updateShine() {
    final bool run = widget.enabled && !busy;
    if (run && !shine.isAnimating) {
      shine.repeat();
    } else if (!run && shine.isAnimating) {
      shine.stop();
    }
  }
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
  }

  Future<void> _confirm() async {
    if (busy || !widget.enabled) {
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      busy = true;
    });
    _updateShine();
    try {
      await widget.onConfirmed();
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
        _updateShine();
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
            color: Colors.white.withValues(alpha: trackFillOpacity),
            border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 0.8),
          ),
          child: Stack(
            children: <Widget>[
              // Phần đã kéo qua: đậm lên theo núm
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: inset + offset + knob,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    color: tint.withValues(alpha: progress * 0.12),
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
                              running: widget.enabled,
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
          // Làm mờ cả trên Android, khác các lớp kính khác: chỉ một lớp nhỏ, như thanh tab
          child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24), child: face),
        );

        // Núm màu chính trên nền trắng
        final Widget thumb = AnimatedScale(
          scale: dragging ? 1.06 : 1,
          duration: const Duration(milliseconds: 140),
          child: Container(
            width: knob,
            height: knob,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tint,
              boxShadow: <BoxShadow>[
                BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 3)),
              ],
            ),
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(15),
                    child: CupertinoActivityIndicator(color: Colors.white),
                  )
                : const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 28),
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

/// Chữ đậm có một dải nhạt trôi mượt từ trái sang phải.
class _ShimmerText extends StatelessWidget {
  final String text;
  final Animation<double> animation;
  final bool running;

  const _ShimmerText({required this.text, required this.animation, required this.running});

  @override
  Widget build(BuildContext context) {
    // Chữ mảnh như iOS; màu thật do ShaderMask quyết (chữ đậm + dải nhạt)
    const TextStyle style = TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w400, letterSpacing: 0.1);
    final Widget label = Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    if (!running) {
      return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style.copyWith(color: shineBaseColor));
    }
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (Rect bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: shineColors,
              stops: shineStops(animation.value),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: label,
    );
  }
}
