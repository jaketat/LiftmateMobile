// BuildContext (Flutter)
import 'package:flutter/widgets.dart';
// go_router: RouteBase, GoRoute, GoRouterState
import 'package:go_router/go_router.dart';

import 'vehicle_detail_screen.dart';
import 'vehicle_doc_form_screen.dart';
import 'vehicles_screen.dart';

// Các màn đội xe (người 4). router.dart gom vào bằng ...fleetRoutes
final List<RouteBase> fleetRoutes = <RouteBase>[
  // X1: danh sách xe
  GoRoute(
    path: '/fleet',
    builder: (BuildContext context, GoRouterState state) {
      return const VehiclesScreen();
    },
  ),
  // X2, X3, X5: chi tiết xe
  GoRoute(
    path: '/fleet/:vehicleId',
    builder: (BuildContext context, GoRouterState state) {
      return VehicleDetailScreen(vehicleId: state.pathParameters['vehicleId']!);
    },
  ),
  // X4: thêm giấy tờ, gia hạn
  GoRoute(
    path: '/fleet/:vehicleId/documents/new',
    builder: (BuildContext context, GoRouterState state) {
      return VehicleDocFormScreen(vehicleId: state.pathParameters['vehicleId']!);
    },
  ),
];
