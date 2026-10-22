import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

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
];
