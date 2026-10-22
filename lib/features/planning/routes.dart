import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'cost_estimate_screen.dart';
import 'plan_screen.dart';

// Màn kế hoạch chia chuyến của người 3. Chi tiết đơn (người 2) mở vào /orders/:orderId/plan
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
];
