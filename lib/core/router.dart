import 'package:flutter/material.dart';
// Riverpod: Provider, Ref, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: GoRouter, GoRoute, GoRouterState
import 'package:go_router/go_router.dart';

import '../features/auth/app_lock.dart';
import '../features/auth/ripple_transition.dart';
import '../features/auth/routes.dart';
import '../features/auth/session_provider.dart';
import '../features/auth/splash_screen.dart';
import '../features/customers/routes.dart';
import '../features/dashboard/routes.dart';
import '../features/dispatch/routes.dart';
import '../features/driver/routes.dart';
import '../features/fleet/routes.dart';
import '../features/maintenance/routes.dart';
import '../features/orders/routes.dart';
import '../features/plan_3d/routes.dart';
import '../features/planning/routes.dart';
import '../features/roles/routes.dart';
import '../features/staff/routes.dart';
import 'menu/main_shell.dart';
import 'menu/menu_items.dart';
import 'menu/more_screen.dart';
import 'session.dart';
import 'widgets/page_transition.dart';

// Màn mở ra sau khi đăng nhập. Mỗi người chạy với --dart-define=START=/orders để mở thẳng màn của mình
const String startLocation = String.fromEnvironment('START', defaultValue: '/');

// Màn vào được khi CHƯA đăng nhập (phase 5 thêm /forgot-password)
const List<String> publicLocations = <String>['/login', '/forgot-password'];

// Provider (Riverpod): hộp đơn giản, tạo 1 lần rồi giữ. Đồ trong hộp là GoRouter
// Trang chỉ có builder: go_router dựng bằng NoTransitionPage (đo trên iPhone, chưa rõ vì sao nó không nhận ra MaterialApp), nên không có hoạt ảnh.
// Đổi hết sang MaterialPage để trượt theo pageTransitionsTheme; riêng gốc của tab và màn khởi động vẫn hiện ngay.
List<RouteBase> withPageTransitions(List<RouteBase> routes) {
  final Set<String> instantPaths = <String>{
    '/',
    '/splash',
    moreTab.path,
    for (final AppMenuItem tab in managerTabs) tab.path,
    for (final AppMenuItem tab in driverTabs) tab.path,
  };
  return <RouteBase>[
    for (final RouteBase route in routes)
      if (route is GoRoute && route.builder != null)
        GoRoute(
          path: route.path,
          name: route.name,
          parentNavigatorKey: route.parentNavigatorKey,
          redirect: route.redirect,
          onExit: route.onExit,
          caseSensitive: route.caseSensitive,
          routes: withPageTransitions(route.routes),
          pageBuilder: (BuildContext context, GoRouterState state) {
            // Builder: để màn nhận context nằm trong trang (ModalRoute.of, context.pop)
            final Widget child = Builder(
              builder: (BuildContext context) {
                final Widget page = route.builder!(context, state);
                if (!isFullScreenDriverTask(route.path)) return page;
                // Không nhận khoảng đệm của thanh tab: quay về màn chính thì thanh tab hiện ra ngay, phần dưới của trang đang thoát sẽ nhảy lên
                return MediaQuery(data: MediaQueryData.fromView(View.of(context)), child: page);
              },
            );
            return instantPaths.contains(route.path) && state.extra != slideInTabRoot
                ? instantPage(key: state.pageKey, child: child)
                : MaterialPage<void>(key: state.pageKey, child: child);
          },
        )
      else
        route,
  ];
}

final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  // ValueNotifier (Flutter): cái chuông đơn giản, đổi value là reo
  final ValueNotifier<int> sessionBell = ValueNotifier<int>(0);

  // ref.listen (Riverpod): hộp session đổi thì chạy hàm này để rung chuông
  ref.listen<AsyncValue<Session?>>(sessionProvider,
      (AsyncValue<Session?>? previous, AsyncValue<Session?> next) {
    sessionBell.value = sessionBell.value + 1;
  });
  // Hết thời gian giữ màn khởi động cũng rung chuông
  ref.listen<AsyncValue<void>>(splashHoldProvider,
      (AsyncValue<void>? previous, AsyncValue<void> next) {
    sessionBell.value = sessionBell.value + 1;
  });
  // Khóa app đổi trạng thái: khóa thì về màn đăng nhập, mở khóa thì vào trong
  ref.listen<AsyncValue<AppLockState>>(appLockProvider, (AsyncValue<AppLockState>? previous, AsyncValue<AppLockState> next) {
    sessionBell.value = sessionBell.value + 1;
  });
  // Hộp router bị hủy thì tháo chuông
  ref.onDispose(sessionBell.dispose);

  return GoRouter(
    // Mở app thì đứng ở sảnh trước
    initialLocation: '/splash',
    // Chuông reo thì go_router hỏi lại bảo vệ (chạy lại redirect)
    refreshListenable: sessionBell,
    // Bảo vệ. Trả về đường dẫn = đuổi sang đó; null = cho qua
    redirect: (BuildContext context, GoRouterState state) {
      // ref.read: chỉ nhìn 1 lần (chuông đã có sessionBell lo)
      final AsyncValue<Session?> sessionValue = ref.read(sessionProvider);
      // Màn người dùng đang muốn vào, vd "/login"
      final String location = state.uri.path;

      // Hộp chưa có kết quả (đang tải hoặc lỗi) hoặc chưa hết giờ giữ màn thì đứng ở sảnh
      final AsyncValue<AppLockState> lockValue = ref.read(appLockProvider);
      if (!sessionValue.hasValue || !ref.read(splashHoldProvider).hasValue || !lockValue.hasValue) {
        if (location == '/splash') {
          return null;
        }
        return '/splash';
      }

      final Session? session = sessionValue.value;

      // Chưa đăng nhập thì chỉ được ở màn công khai, còn lại ra /login
      if (session == null) {
        if (publicLocations.contains(location)) {
          return null;
        }
        return '/login';
      }

      // Bật khóa app: dừng ở màn đăng nhập (quên mật khẩu vẫn mở được) tới khi xác thực xong
      if (lockValue.value!.blocks(session)) {
        return publicLocations.contains(location) ? null : '/login';
      }

      // Đang dùng mật khẩu tạm thì nhốt ở màn đổi mật khẩu (server cũng chặn mọi API khác)
      if (session.mustChangePassword) {
        if (location == '/change-password') {
          return null;
        }
        return '/change-password';
      }

      // Đã đăng nhập mà còn đứng ở sảnh, quầy đăng nhập hoặc "/" thì đưa vào màn đầu tiên
      if (location == '/' || location == '/splash' || publicLocations.contains(location)) {
        // Vừa mở khóa sau khi rời app lâu: trả về màn đang đứng
        final String? returnTo = ref.read(appLockProvider.notifier).takeReturnLocation();
        if (returnTo != null) {
          return returnTo;
        }
        // Không chạy với START thì vào tab đầu tiên người này được xem
        if (startLocation == '/') {
          return tabsFor(session).first.path;
        }
        return startLocation;
      }

      // Đã đăng nhập, đang vào màn bình thường thì cho qua
      return null;
    },
    // Đường dẫn chưa có màn (người khác chưa làm) thì hiện "Màn này đang làm", vẫn có thanh tab
    errorBuilder: (BuildContext context, GoRouterState state) {
      return MainShell(
        location: state.uri.path,
        child: NotReadyScreen(location: state.uri.path),
      );
    },
    routes: withPageTransitions(<RouteBase>[
      // Không bao giờ hiện: bảo vệ luôn đưa "/" sang tab đầu tiên
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) {
          return const SizedBox.shrink();
        },
      ),
      // Đăng nhập, đổi mật khẩu: nằm ngoài khung, không có thanh tab
      ...authRoutes,
      // ShellRoute (go_router): mọi màn bên trong đều được bọc bởi MainShell (có thanh tab dưới)
      ShellRoute(
        // Từ màn khởi động hoặc đăng nhập vào đây: gợn sáng lên tới đâu, màn chính hiện tới đó
        pageBuilder: (BuildContext context, GoRouterState state, Widget child) {
          return rippleTransitionPage(
            key: state.pageKey,
            heavy: true,
            child: MainShell(location: state.uri.path, child: child),
          );
        },
        routes: withPageTransitions(<RouteBase>[
          GoRoute(
            path: '/more',
            builder: (BuildContext context, GoRouterState state) {
              return const MoreScreen();
            },
          ),
          ...rolesRoutes,
          ...plan3dRoutes,
          ...ordersRoutes,
          ...driverRoutes,
          ...planningRoutes,
          ...dispatchRoutes,
          ...customersRoutes,
          ...fleetRoutes,
          ...staffRoutes,
          ...dashboardRoutes,
          ...maintenanceRoutes,
        ]),
      ),
    ]),
  );
});
