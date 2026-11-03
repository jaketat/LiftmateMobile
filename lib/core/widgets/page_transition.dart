// Chuyển cảnh chung của mọi trang: trượt ngang và vuốt mép quay lại kiểu iOS, trên cả iOS và Android.
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';

class AppPageTransitions extends CupertinoPageTransitionsBuilder {
  const AppPageTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return super.buildTransitions<T>(
      route,
      context,
      animation,
      secondaryAnimation,
      RouteMotionGate(
        animation: animation,
        // Không dùng tham số secondaryAnimation: trang kế có delegatedTransition thì Flutter truyền vào một animation giả đứng yên
        secondaryAnimation: route.secondaryAnimation!,
        userGesture: route.navigator?.userGestureInProgressNotifier,
        child: child,
      ),
    );
  }
}

/// Padding cho danh sách có padding riêng: trang chạy dưới thanh tab kính, thêm khoảng đáy để dòng cuối cuộn lên được.
/// ListView không khai padding thì Flutter tự cộng khoảng này.
EdgeInsets withTabBarInset(BuildContext context, EdgeInsets padding) {
  return padding.copyWith(bottom: padding.bottom + MediaQuery.paddingOf(context).bottom);
}

/// Dấu cho biết gốc tab này được mở từ nút trong trang, cần trượt vào như trang thường
const Object slideInTabRoot = 'slideInTabRoot';

/// Từ nút trong trang mở gốc một tab, vd "Đơn đang chạy" ở trang chủ. Trượt vào, có nút quay lại và vuốt mép về trang cũ.
/// context.go đổi hẳn tab nên hiện ngay, hợp với thanh tab chứ không hợp với nút trong trang.
Future<void> pushTabRoot(BuildContext context, String path) => context.push<void>(path, extra: slideInTabRoot);

/// Trang hiện ngay, không trượt: gốc của mỗi tab và màn khởi động. Vẫn báo trạng thái di chuyển, vì trang bị trang con che và lộ lại.
CustomTransitionPage<void> instantPage({required LocalKey key, required Widget child}) {
  return CustomTransitionPage<void>(
    key: key,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    child: child,
    transitionsBuilder: (BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
      final ModalRoute<dynamic> route = ModalRoute.of(context)!;
      return RouteMotionGate(
        animation: animation,
        // Như AppPageTransitions: lấy animation thật của route
        secondaryAnimation: route.secondaryAnimation!,
        userGesture: route.navigator?.userGestureInProgressNotifier,
        child: child,
      );
    },
  );
}

/// Trang kiểu sheet của iOS: trượt từ dưới lên, màn phía sau tối đi và vẫn thấy được
CustomTransitionPage<void> sheetPage({required LocalKey key, required Widget child}) {
  return CustomTransitionPage<void>(
    key: key,
    opaque: false,
    barrierColor: const Color(0x4D000000),
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    child: child,
    transitionsBuilder: (BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
      final ModalRoute<dynamic> route = ModalRoute.of(context)!;
      return SlideTransition(
        position: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)
            .drive(Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)),
        child: RouteMotionGate(
          animation: animation,
          secondaryAnimation: route.secondaryAnimation!,
          userGesture: route.navigator?.userGestureInProgressNotifier,
          child: child,
        ),
      );
    },
  );
}

/// Báo cho các nút bên trong trang biết trang đang di chuyển hay đang đứng yên.
/// Đo trên iPhone 17 Pro Max: có các view native của nút thì trượt lệch nhịp 25–44ms, bỏ chúng đi thì đều 8ms (120Hz),
/// nên nút native chỉ có mặt lúc trang đứng yên (xem nativeViewsAllowed trong glass.dart).
class RouteMotionGate extends StatefulWidget {
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final ValueListenable<bool>? userGesture;
  final Widget child;

  const RouteMotionGate({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.userGesture,
    required this.child,
  });

  /// Trang chứa [context] đang trượt, bị trang khác che, hoặc đang được vuốt mép
  static bool movingOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_RouteMotion>()?.moving ?? false;
  }

  @override
  State<RouteMotionGate> createState() => _RouteMotionGateState();
}

class _RouteMotionGateState extends State<RouteMotionGate> {
  // Hai khung đầu của trang mới: Navigator chưa kịp cho animation chạy nên trang trông như đứng yên,
  // vẫn tính là đang di chuyển để khỏi tạo view native rồi lại bỏ
  bool moving = true;
  bool settled = false;

  bool get currentlyMoving {
    return !widget.animation.isCompleted || !widget.secondaryAnimation.isDismissed || (widget.userGesture?.value ?? false);
  }

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(onStatus);
    widget.secondaryAnimation.addStatusListener(onStatus);
    widget.userGesture?.addListener(refresh);
    SchedulerBinding.instance.addPostFrameCallback((Duration _) {
      SchedulerBinding.instance.addPostFrameCallback((Duration _) {
        settled = true;
        if (mounted) refresh();
      });
      SchedulerBinding.instance.scheduleFrame();
    });
  }

  @override
  void didUpdateWidget(covariant RouteMotionGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    oldWidget.animation.removeStatusListener(onStatus);
    oldWidget.secondaryAnimation.removeStatusListener(onStatus);
    oldWidget.userGesture?.removeListener(refresh);
    widget.animation.addStatusListener(onStatus);
    widget.secondaryAnimation.addStatusListener(onStatus);
    widget.userGesture?.addListener(refresh);
    refresh();
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(onStatus);
    widget.secondaryAnimation.removeStatusListener(onStatus);
    widget.userGesture?.removeListener(refresh);
    super.dispose();
  }

  void onStatus(AnimationStatus status) => refresh();

  void refresh() {
    if (!settled) return;
    // Navigator đổi trang ngay trong lúc dựng khung hình: lúc đó chưa được setState, đợi hết khung
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((Duration _) {
        if (mounted) refresh();
      });
      return;
    }
    if (moving == currentlyMoving) return;
    setState(() {
      moving = currentlyMoving;
    });
  }

  @override
  Widget build(BuildContext context) => _RouteMotion(moving: moving, child: widget.child);
}

/// Đợi trang trượt vào xong mới dựng [child] lần đầu. Sau đó giữ nguyên, kể cả lúc trang bị che hay đang thoát.
class AfterRouteEntrance extends StatefulWidget {
  final Widget child;
  final Widget placeholder;

  const AfterRouteEntrance({super.key, required this.child, required this.placeholder});

  @override
  State<AfterRouteEntrance> createState() => _AfterRouteEntranceState();
}

class _AfterRouteEntranceState extends State<AfterRouteEntrance> {
  bool entered = false;

  @override
  Widget build(BuildContext context) {
    entered = !RouteMotionGate.movingOf(context) || entered;
    return entered ? widget.child : widget.placeholder;
  }
}

/// Tạm dùng bản Flutter vẽ cho các nút bên trong khi [paused] bật (vd phần đang bị kéo theo sheet),
/// cùng lý do với lúc trang trượt: view native di chuyển theo từng khung làm lệch nhịp
class NativeViewsPause extends StatelessWidget {
  final ValueListenable<bool> paused;
  final Widget child;

  const NativeViewsPause({super.key, required this.paused, required this.child});

  @override
  Widget build(BuildContext context) {
    final bool routeMoving = RouteMotionGate.movingOf(context);
    return ValueListenableBuilder<bool>(
      valueListenable: paused,
      builder: (BuildContext context, bool value, Widget? content) => _RouteMotion(moving: routeMoving || value, child: content!),
      child: child,
    );
  }
}

class _RouteMotion extends InheritedWidget {
  final bool moving;

  const _RouteMotion({required this.moving, required super.child});

  @override
  bool updateShouldNotify(_RouteMotion oldWidget) => oldWidget.moving != moving;
}
