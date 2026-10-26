import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../plan_3d/routes.dart' show tripKeyFrom;
import 'assign_screen.dart';
import 'cost_estimate_screen.dart';
import 'plan_screen.dart';
import 'plan_trip_screen.dart';
import 'run_trips_screen.dart';

// Màn kế hoạch chia chuyến, tiền dầu, điều xe của người 3. Chi tiết đơn (người 2) mở vào /orders/:orderId/plan
final List<RouteBase> planningRoutes = <RouteBase>[
  GoRoute(
    path: '/orders/:orderId/plan',
    builder: (BuildContext context, GoRouterState state) {
      return PlanScreen(orderId: state.pathParameters['orderId']!);
    },
  ),
  // Tiền dầu khứ hồi: mở từ khung tổng của màn kế hoạch
  GoRoute(
    path: '/orders/:orderId/plans/:planId/cost',
    builder: (BuildContext context, GoRouterState state) {
      return CostEstimateScreen(
        planKey: (
          orderId: state.pathParameters['orderId']!,
          planId: state.pathParameters['planId']!,
        ),
      );
    },
  ),
  // Chi tiết một chuyến trong kế hoạch (K2). Hai nút 3D, 2D của người 1 dùng đường dẫn con /3d, /2d
  GoRoute(
    path: '/orders/:orderId/plans/:planId/trips/:tripId',
    builder: (BuildContext context, GoRouterState state) {
      return PlanTripScreen(tripKey: tripKeyFrom(state));
    },
  ),
  // Chuyến chạy của đơn: tạo từ kế hoạch, chốt lịch (K5, K8). Màn "Điều phối hôm nay" cũng mở vào đây
  GoRoute(
    path: '/orders/:orderId/dispatch-trips',
    builder: (BuildContext context, GoRouterState state) {
      return RunTripsScreen(orderId: state.pathParameters['orderId']!);
    },
  ),
  // Gán xe, tài xế cho một chuyến chạy (K6, K7)
  GoRoute(
    path: '/orders/:orderId/dispatch-trips/:tripId/assign',
    builder: (BuildContext context, GoRouterState state) {
      return AssignScreen(
        orderId: state.pathParameters['orderId']!,
        tripId: state.pathParameters['tripId']!,
      );
    },
  ),
];
