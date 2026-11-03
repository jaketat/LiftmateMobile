// Màn của app tài xế (Người 2). router.dart đã gom sẵn bằng ...driverRoutes.
// /driver/trips/:tripId/breakdown, /driver/breakdowns, /driver/breakdowns/new là của Người 5 (maintenance/routes.dart).
// Đường dẫn có chữ cố định đứng trước đường dẫn có :tripId.
import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';

import '../auth/profile_screen.dart';
import 'driver_home_screen.dart';
import 'location_consent_screen.dart';
import 'my_documents_screen.dart';
import 'sessions_screen.dart';
import 'trip_detail_screen.dart';
import 'trip_documents_screen.dart';

final driverRoutes = <RouteBase>[
  // T1: tab "Chuyến" của tài xế: bản đồ + sheet chuyến
  GoRoute(
    path: '/driver/trips',
    builder: (BuildContext context, GoRouterState state) => const DriverHomeScreen(),
  ),
  // T7: đồng ý / tắt chia sẻ vị trí
  GoRoute(
    path: '/driver/location-consent',
    builder: (BuildContext context, GoRouterState state) => const LocationConsentScreen(),
  ),
  // T5: ảnh hiện trường, biên bản giao hàng của một chuyến
  GoRoute(
    path: '/driver/trips/:tripId/documents',
    builder: (BuildContext context, GoRouterState state) {
      return TripDocumentsScreen(tripId: state.pathParameters['tripId']!);
    },
  ),
  // T2–T4, T8: chuyến đang chạy trên bản đồ
  GoRoute(
    path: '/driver/trips/:tripId',
    // Không dùng trang tự dựng (CustomTransitionPage): bản đồ ở màn chuyến không canh được khung và tuyến, chưa rõ nguyên nhân
    builder: (BuildContext context, GoRouterState state) {
      return TripDetailScreen(tripId: state.pathParameters['tripId']!);
    },
  ),
  // Tài khoản: giấy tờ của tôi, thiết bị đang đăng nhập (mở từ màn Tài khoản / Thêm)
  GoRoute(
    path: '/account/profile',
    builder: (BuildContext context, GoRouterState state) => const ProfileScreen(),
  ),
  GoRoute(
    path: '/account/documents',
    builder: (BuildContext context, GoRouterState state) => const MyDocumentsScreen(),
  ),
  GoRoute(
    path: '/account/devices',
    builder: (BuildContext context, GoRouterState state) => const SessionsScreen(),
  ),
];
