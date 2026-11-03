// Màn khởi động, giống phần đầu trang liftmate.com.vn: nền trắng, chấm màu trôi, móc cẩu thả xuống,
// hai người bước vào, chữ LiftMate hiện từng ký tự. Trong lúc đó hộp session hỏi server.
// Mất mạng thì hiện lỗi + "Thử lại". Splash gốc của máy để trắng trơn, nên logo lắp ráp ngay từ đầu.
import 'package:flutter/material.dart';
// SystemUiOverlayStyle: chữ thanh trạng thái màu tối trên nền trắng
import 'package:flutter/services.dart';
// Riverpod: ConsumerStatefulWidget, FutureProvider, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/liftmate_mark.dart';
import 'session_provider.dart';

// Giữ màn này đến khi logo lắp xong (khoảng 1,27 giây): chưa đăng nhập thì session xong ngay, logo sẽ bị cắt ngang.
// Không để lâu hơn: người dùng mở app nhiều lần mỗi ngày, chờ lâu sẽ thấy app chậm.
// Router đợi hộp này có kết quả rồi mới cho rời màn.
final FutureProvider<void> splashHoldProvider = FutureProvider<void>((Ref ref) {
  return Future<void>.delayed(const Duration(milliseconds: 1350));
});

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() {
    return _SplashScreenState();
  }
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  // Đồng hồ: value = mốc trong kịch bản logo (1,9 là lắp xong). Chạy nhanh gấp 1,5 lần giây thật
  // nên logo lắp xong sau khoảng 1,27 giây: đủ nhanh mà vẫn uyển chuyển. Mọi chuyển động đều tính từ con số này
  late final AnimationController clock = AnimationController(
    vsync: this,
    upperBound: 3600,
    duration: const Duration(minutes: 40),
  );
  bool started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (started) {
      return;
    }
    started = true;
    // Máy tắt hiệu ứng thì hiện luôn logo đã lắp xong, không chạy gì
    if (MediaQuery.disableAnimationsOf(context)) {
      clock.value = 2;
    } else {
      clock.forward();
    }
  }

  @override
  void dispose() {
    clock.dispose();
    restoreDefaultStatusBar();
    super.dispose();
  }

  // Logo đang bay: giữ đúng tư thế đung đưa hiện tại, trong lúc bay dịu dần về tư thế đứng yên
  Widget markFlight(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromContext,
    BuildContext toContext,
  ) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        return CustomPaint(
          key: const ValueKey<String>('mark-flight'),
          size: Size.infinite,
          painter: LiftMateMarkPainter(clock: clock, settle: animation.value),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Nhìn hộp + nghe chuông: hộp đổi từ "đang tải" sang "lỗi" thì màn tự vẽ lại
    final AsyncValue<Session?> sessionValue = ref.watch(sessionProvider);
    // Bấm Thử lại thì hộp vẫn nhớ lỗi cũ trong lúc tải: phải xem cả isLoading
    final bool failed = sessionValue.hasError && !sessionValue.isLoading;
    // Đồng hồ của màn kế tiếp đang hiện ra đè lên màn này
    final Animation<double> leaving = ModalRoute.of(context)?.secondaryAnimation ?? kAlwaysDismissedAnimation;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: whiteScreenStatusBar,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const LiftMateSparks(),
            // Vào màn chính thì logo không có chỗ bay tới: bay lên theo gợn sáng rồi mờ dần
            AnimatedBuilder(
              animation: leaving,
              builder: (BuildContext context, Widget? brand) {
                final double rise = Curves.easeOutCubic.transform(leaving.value);
                return Transform.translate(
                  offset: Offset(0, -MediaQuery.sizeOf(context).height * 0.6 * rise),
                  child: Opacity(opacity: 1 - motionPhase(leaving.value, 0.15, 0.5), child: brand),
                );
              },
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Hero (Flutter): logo và chữ bay sang đúng chỗ của chúng trên màn đăng nhập
                    Hero(
                      tag: markHeroTag,
                      flightShuttleBuilder: markFlight,
                      child: RepaintBoundary(
                        child: CustomPaint(size: const Size(104, 206), painter: LiftMateMarkPainter(clock: clock)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Hero(
                      tag: wordHeroTag,
                      child: LiftMateWord(fontSize: 44, clock: clock),
                    ),
                  ],
                ),
              ),
            ),
            // Phần dưới: mạng chậm thì vạch chờ, lỗi thì câu lỗi + nút
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                  child: failed
                      ? _SessionError(
                          message: errorMessage(sessionValue.error!),
                          onRetry: () {
                            // ref.invalidate (Riverpod): đổ hộp đi → build() của SessionNotifier chạy lại
                            ref.invalidate(sessionProvider);
                          },
                        )
                      : AnimatedBuilder(
                          animation: clock,
                          builder: (BuildContext context, Widget? loader) {
                            // Hiện sau khi màn đã kịp chuyển đi (giữ 1,35 giây + chuyển 0,9 giây, tính ra mốc 3,4 của đồng hồ): mạng nhanh thì không thấy vạch chờ
                            return Opacity(opacity: motionPhase(clock.value, 3.4, 0.45), child: loader);
                          },
                          child: const _Loader(),
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

// Lỗi (mất mạng, server bận): token vẫn giữ, bấm Thử lại là hỏi lại server
class _SessionError extends StatelessWidget {
  const _SessionError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppColors.text, height: 1.45),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: onRetry, child: Text(t('common.retry'))),
      ],
    );
  }
}

// Vạch chờ: đoạn cam chạy mãi trên một đường mảnh
class _Loader extends StatefulWidget {
  const _Loader();

  @override
  State<_Loader> createState() {
    return _LoaderState();
  }
}

class _LoaderState extends State<_Loader> with SingleTickerProviderStateMixin {
  late final AnimationController loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void initState() {
    super.initState();
    loop.repeat();
  }

  @override
  void dispose() {
    loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(size: const Size(120, 3), painter: _LoaderPainter(loop)),
    );
  }
}

class _LoaderPainter extends CustomPainter {
  // repaint: đồng hồ chạy thì chỉ vẽ lại, không build lại widget
  _LoaderPainter(this.progress) : super(repaint: progress);

  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final double y = size.height / 2;
    final Paint track = Paint()
      ..color = AppColors.border
      ..strokeWidth = size.height
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), track);

    // Đoạn cam dài bằng 1/3 đường, đi từ ngoài mép trái sang ngoài mép phải rồi cắt gọn trong đường
    final double segment = size.width / 3;
    final double head = Curves.easeInOut.transform(progress.value) * (size.width + segment);
    final double left = (head - segment).clamp(0, size.width);
    final double right = head.clamp(0, size.width);
    if (right > left) {
      final Paint active = Paint()
        ..color = AppColors.orange
        ..strokeWidth = size.height
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(left, y), Offset(right, y), active);
    }
  }

  @override
  bool shouldRepaint(_LoaderPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
