import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/routes.dart';
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

final router = GoRouter(
  routes: [
    // Tạm: màn trống. Phase 3 đổi thành đăng nhập, Phase 4 đổi thành menu.
    GoRoute(
      path: '/',
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('LiftMate'))),
    ),
    ...authRoutes,
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
  ],
);
