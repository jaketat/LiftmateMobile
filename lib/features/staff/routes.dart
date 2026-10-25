// BuildContext (Flutter)
import 'package:flutter/widgets.dart';
// go_router: RouteBase, GoRoute, GoRouterState
import 'package:go_router/go_router.dart';

import 'staff_detail_screen.dart';
import 'staff_screen.dart';

// Các màn nhân sự (người 4). router.dart gom vào bằng ...staffRoutes
final List<RouteBase> staffRoutes = <RouteBase>[
  // S1: danh sách nhân sự
  GoRoute(
    path: '/staff',
    builder: (BuildContext context, GoRouterState state) {
      return const StaffScreen();
    },
  ),
  // S2: chi tiết nhân sự
  GoRoute(
    path: '/staff/:userId',
    builder: (BuildContext context, GoRouterState state) {
      return StaffDetailScreen(userId: state.pathParameters['userId']!);
    },
  ),
];
