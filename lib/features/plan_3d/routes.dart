// BuildContext (Flutter)
import 'package:flutter/widgets.dart';
// go_router: RouteBase, GoRoute, GoRouterState
import 'package:go_router/go_router.dart';

import 'blueprint_screen.dart';
import 'plan_3d_api.dart';
import 'trip_3d_screen.dart';

// Đọc 3 id từ đường dẫn thành TripKey
TripKey tripKeyFrom(GoRouterState state) {
  return (
    orderId: state.pathParameters['orderId']!,
    planId: state.pathParameters['planId']!,
    tripId: state.pathParameters['tripId']!,
  );
}

// Màn 2D, 3D (người 1). Người 3 mở từ chi tiết chuyến (doc mục 1.5), chỉ truyền id
final List<RouteBase> plan3dRoutes = <RouteBase>[
  GoRoute(
    path: '/orders/:orderId/plans/:planId/trips/:tripId/2d',
    builder: (BuildContext context, GoRouterState state) {
      return BlueprintScreen(tripKey: tripKeyFrom(state));
    },
  ),
  GoRoute(
    path: '/orders/:orderId/plans/:planId/trips/:tripId/3d',
    builder: (BuildContext context, GoRouterState state) {
      return Trip3DScreen(tripKey: tripKeyFrom(state));
    },
  ),
];
