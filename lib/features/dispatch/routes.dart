import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'close_order_screen.dart';
import 'dispatch_today_screen.dart';
import 'trip_track_screen.dart';

// Màn điều phối của người 3. Menu (người 1) trỏ vào /dispatch/today
final List<RouteBase> dispatchRoutes = <RouteBase>[
  GoRoute(
    path: '/dispatch/today',
    builder: (BuildContext context, GoRouterState state) {
      return const DispatchTodayScreen();
    },
  ),
  // Theo dõi chuyến: mở từ "Điều phối hôm nay" hoặc nút "Theo dõi" ở danh sách chuyến chạy (doc mục 3.13)
  GoRoute(
    path: '/orders/:orderId/trips/:tripId/track',
    builder: (BuildContext context, GoRouterState state) {
      return TripTrackScreen(
        trackKey: (
          orderId: state.pathParameters['orderId']!,
          tripId: state.pathParameters['tripId']!,
        ),
      );
    },
  ),
  // Chốt đơn và hóa đơn: mở từ nút "Chốt đơn và hóa đơn" ở chi tiết đơn (người 2) (doc mục 3.14)
  GoRoute(
    path: '/orders/:orderId/close',
    builder: (BuildContext context, GoRouterState state) {
      return CloseOrderScreen(orderId: state.pathParameters['orderId']!);
    },
  ),
];
