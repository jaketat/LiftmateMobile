import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'dispatch_today_screen.dart';

// Màn điều phối của người 3. Menu (người 1) trỏ vào /dispatch/today
final List<RouteBase> dispatchRoutes = <RouteBase>[
  GoRoute(
    path: '/dispatch/today',
    builder: (BuildContext context, GoRouterState state) {
      return const DispatchTodayScreen();
    },
  ),
];
