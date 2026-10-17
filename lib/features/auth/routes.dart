import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'splash_screen.dart';
import 'login_screen.dart';
import 'change_password_screen.dart';
import 'forgot_password_screen.dart';

final authRoutes = <RouteBase>[
  GoRoute(
    path: '/splash',
    builder: (BuildContext context, GoRouterState state) {
      return const SplashScreen();
    },
  ),
  GoRoute(
    path: '/login',
    builder: (BuildContext context, GoRouterState state) {
      return const LoginScreen();
    },
  ),
  // Màn đổi mật khẩu: bị bắt đổi hoặc tự đổi
  GoRoute(
    path: '/change-password',
    builder: (BuildContext context, GoRouterState state) {
      return const ChangePasswordScreen();
    },
  ),
  // Màn quên mật khẩu (chưa đăng nhập cũng vào được)
  GoRoute(
    path: '/forgot-password',
    builder: (BuildContext context, GoRouterState state) {
      return const ForgotPasswordScreen();
    },
  ),
];
