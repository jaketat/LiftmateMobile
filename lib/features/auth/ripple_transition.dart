// Hiệu ứng lúc rời màn khởi động sang màn đăng nhập hoặc màn chính, kiểu Apple Intelligence: gợn sáng bắn từ
// cạnh dưới điện thoại lên, viền sáng hiện theo ngay sau rồi tắt dần.
// Màu là bộ --ai-1 … --ai-5 của LiftMate Intelligence trên web.
import 'dart:async';

import 'package:ai_glow/ai_glow.dart';
import 'package:flutter/material.dart';
// go_router: CustomTransitionPage
import 'package:go_router/go_router.dart';

import '../../core/widgets/liftmate_mark.dart';

// Đầu gợn sáng đang ở đâu, tính theo chiều cao màn từ cạnh dưới lên (0 = cạnh dưới, trên 1 = đã qua đỉnh).
// progress: tiến độ chuyển màn, 0–1
double rippleFront(double progress) {
  final double moving = ((progress - 0.12) / 0.88).clamp(0.0, 1.0);
  return Curves.easeOutSine.transform(moving) * 1.35;
}

// Gợn kéo ngang để phủ hết bề ngang màn ngay từ đầu
const double waveStretch = 1.6;

// true: màn chính đang lộ ra theo sóng. Bản đồ đợi cờ này tắt rồi mới tạo (xem AfterEntrance)
final ValueNotifier<bool> entranceRunning = ValueNotifier<bool>(false);

// Trang mới lộ ra theo đúng đầu gợn sáng: sóng lên tới đâu, trang hiện tới đó.
// heavy: trang nặng như màn chính (bản đồ, nhiều lớp kính blur). Vẽ sống trong lúc lộ sẽ giật mạnh,
// nên chụp trang thành ảnh để sóng chỉ lộ ảnh tĩnh, và bỏ viền blur của gợn
CustomTransitionPage<void> rippleTransitionPage({required LocalKey key, required Widget child, bool heavy = false}) {
  return CustomTransitionPage<void>(
    key: key,
    transitionDuration: const Duration(milliseconds: 900),
    child: child,
    transitionsBuilder: (
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
    ) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _WaveReveal(animation: animation, heavy: heavy, child: child),
          IgnorePointer(child: RippleOverlay(animation: animation, glow: !heavy)),
        ],
      );
    },
  );
}

// Đợi màn chính lộ xong mới dựng con. Tạo bản đồ lúc sóng đang chạy là nguyên nhân chính gây giật
class AfterEntrance extends StatelessWidget {
  const AfterEntrance({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: entranceRunning,
      builder: (BuildContext context, bool running, Widget? ready) {
        return running ? const SizedBox.expand() : ready!;
      },
      child: child,
    );
  }
}

// Cắt trang theo hình gợn sóng
class _WaveReveal extends StatefulWidget {
  const _WaveReveal({required this.animation, required this.heavy, required this.child});

  final Animation<double> animation;
  final bool heavy;
  final Widget child;

  @override
  State<_WaveReveal> createState() {
    return _WaveRevealState();
  }
}

class _WaveRevealState extends State<_WaveReveal> {
  // Khung hình đầu tiên đồng hồ có thể chưa chạy mà đang ở mốc 1: giấu trang, tránh chớp cả màn
  bool firstFrame = true;
  bool sawForward = false;
  final SnapshotController snapshot = SnapshotController(allowSnapshotting: true);
  // Phòng khi trang vào không có chuyển động: không để bản đồ đợi mãi
  Timer? fallback;

  @override
  void initState() {
    super.initState();
    if (widget.heavy) {
      entranceRunning.value = true;
      widget.animation.addStatusListener(onStatus);
      fallback = Timer(const Duration(milliseconds: 1500), finish);
    }
    WidgetsBinding.instance.addPostFrameCallback((Duration time) {
      if (mounted) {
        setState(() {
          firstFrame = false;
        });
      }
    });
  }

  void onStatus(AnimationStatus status) {
    if (status == AnimationStatus.forward) {
      sawForward = true;
    } else if (status == AnimationStatus.completed && sawForward) {
      finish();
    }
  }

  // Lộ xong: thôi dùng ảnh chụp, cho bản đồ tạo
  void finish() {
    fallback?.cancel();
    snapshot.allowSnapshotting = false;
    entranceRunning.value = false;
  }

  @override
  void dispose() {
    fallback?.cancel();
    widget.animation.removeStatusListener(onStatus);
    if (widget.heavy) {
      entranceRunning.value = false;
    }
    snapshot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.animation,
      builder: (BuildContext context, Widget? page) {
        final bool revealing = widget.animation.status == AnimationStatus.forward;
        // Clip.none: xong rồi thì không cắt nữa, nhưng vẫn giữ nguyên cây widget để trang không bị dựng lại
        return ClipPath(
          clipper: _WaveClipper(firstFrame ? 0 : rippleFront(widget.animation.value)),
          clipBehavior: firstFrame || revealing ? Clip.antiAlias : Clip.none,
          child: page,
        );
      },
      child: widget.heavy
          ? SnapshotWidget(controller: snapshot, mode: SnapshotMode.permissive, child: widget.child)
          : widget.child,
    );
  }
}

class _WaveClipper extends CustomClipper<Path> {
  _WaveClipper(this.front);

  final double front;

  @override
  Path getClip(Size size) {
    final double radius = size.height * front;
    return Path()
      ..addOval(Rect.fromCenter(
        center: Offset(size.width / 2, size.height),
        width: radius * waveStretch * 2,
        height: radius * 2,
      ));
  }

  @override
  bool shouldReclip(_WaveClipper oldClipper) {
    return oldClipper.front != front;
  }
}

class RippleOverlay extends StatelessWidget {
  const RippleOverlay({super.key, required this.animation, this.glow = true});

  // Đồng hồ chuyển màn của go_router
  final Animation<double> animation;
  // Có vẽ viền blur ai_glow không
  final bool glow;

  // Đầu viền mờ dần trên một đoạn bằng 1/6 chiều cao màn, không bị cắt sắc
  static const double feather = 1 / 6;

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? border) {
        // Chỉ chạy lúc vào màn. Xong rồi hoặc đang rời màn thì bỏ hẳn, không tốn gì
        if (animation.status != AnimationStatus.forward) {
          return const SizedBox.shrink();
        }
        final double head = rippleFront(animation.value) - feather;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (glow) Opacity(
              opacity: 1 - motionPhase(animation.value, 0.65, 0.35, Curves.easeOut),
              // ShaderMask (Flutter): chỉ hiện phần viền nằm dưới đầu đang bắn lên
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (Rect bounds) {
                  return LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: const <Color>[Colors.white, Colors.white, Colors.transparent],
                    stops: <double>[0, head.clamp(0.0, 1.0), (head + feather).clamp(0.0, 1.0)],
                  ).createShader(bounds);
                },
                child: border,
              ),
            ),
            CustomPaint(painter: _RipplePainter(animation.value)),
          ],
        );
      },
      child: !glow ? null : InnerAiGlowing(
        width: size.width,
        height: size.height,
        borderRadius: 32,
        glowWidth: 10,
        blure: 14,
        colors: const <Color>[
          Color(0xFFFF8A3C),
          Color(0xFFFF4F8B),
          Color(0xFFA45CFF),
          Color(0xFF3D8BFF),
          Color(0xFF2AC8E8),
        ],
        child: const SizedBox.expand(),
      ),
    );
  }
}

// Dải nhiều màu trong suốt loang từ cạnh dưới lên, rồi tan dần.
// Không dùng BlendMode.multiply: màn chính có bản đồ (platform view), trộn kiểu đó có thể ra mảng trắng đục
class _RipplePainter extends CustomPainter {
  _RipplePainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final double front = rippleFront(progress);
    final double fade = 1 - motionPhase(progress, 0.6, 0.4, Curves.easeOut);
    if (front == 0 || fade == 0) {
      return;
    }
    final double radius = size.height * front;
    // Dải màu dày bằng 40% chiều cao màn, phía sau đầu gợn
    final double inner = (1 - size.height * 0.4 / radius).clamp(0.0, 1.0);
    final double step = (1 - inner) / 6;
    final Paint paint = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          const Color(0xFF2AC8E8).withValues(alpha: 0),
          const Color(0xFF2AC8E8).withValues(alpha: 0.16 * fade),
          const Color(0xFF3D8BFF).withValues(alpha: 0.2 * fade),
          const Color(0xFFA45CFF).withValues(alpha: 0.22 * fade),
          const Color(0xFFFF4F8B).withValues(alpha: 0.22 * fade),
          const Color(0xFFFF8A3C).withValues(alpha: 0.24 * fade),
          const Color(0xFFFF8A3C).withValues(alpha: 0),
        ],
        stops: <double>[
          inner,
          inner + step,
          inner + step * 2,
          inner + step * 3,
          inner + step * 4,
          inner + step * 5,
          1,
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius));

    canvas.save();
    // Tâm ở giữa cạnh dưới
    canvas.translate(size.width / 2, size.height);
    canvas.scale(waveStretch, 1);
    canvas.drawCircle(Offset.zero, radius, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RipplePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
