import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'splash_screen.dart';
import 'login_screen.dart';

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
];
