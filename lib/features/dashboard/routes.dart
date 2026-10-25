// BuildContext (Flutter)
import 'package:flutter/widgets.dart';
// go_router: RouteBase, GoRoute, GoRouterState
import 'package:go_router/go_router.dart';

import 'alerts_screen.dart';
import 'dashboard_screen.dart';
import 'revenue_screen.dart';

// Trang chủ, doanh thu, cảnh báo (người 4). router.dart gom vào bằng ...dashboardRoutes
final List<RouteBase> dashboardRoutes = <RouteBase>[
  // B1: trang chủ
  GoRoute(
    path: '/dashboard',
    builder: (BuildContext context, GoRouterState state) {
      return const DashboardScreen();
    },
  ),
  // B2: doanh thu theo năm
  GoRoute(
    path: '/dashboard/revenue',
    builder: (BuildContext context, GoRouterState state) {
      return const RevenueScreen();
    },
  ),
  // B3: cảnh báo giấy tờ
  GoRoute(
    path: '/dashboard/alerts',
    builder: (BuildContext context, GoRouterState state) {
      return const AlertsScreen();
    },
  ),
];
