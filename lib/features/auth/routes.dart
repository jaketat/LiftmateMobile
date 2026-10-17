import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'login_screen.dart';

final authRoutes = <RouteBase>[
  GoRoute(
    path: '/login',
    builder: (BuildContext context, GoRouterState state) {
      return const LoginScreen();
    },
  ),
];
