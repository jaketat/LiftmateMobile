import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/routes.dart';
import '../features/auth/session_provider.dart';
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
import 'session.dart';

final GoRouter router = GoRouter(
  initialLocation: '/login',
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) {
        return const HomePlaceholder();
      },
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

class HomePlaceholder extends ConsumerWidget {
  const HomePlaceholder({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ref.watch: đọc đồ trong hộp + nghe chuông. .value = Session hoặc null
    final Session? session = ref.watch(sessionProvider).value;

    String text = 'Chưa đăng nhập';
    if (session != null) {
      text = 'Xin chào ${session.fullName}\n${session.roleName} – ${session.companyName}';
    }

    return Scaffold(
      body: Center(
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}