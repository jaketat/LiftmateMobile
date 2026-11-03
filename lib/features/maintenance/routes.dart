// 9 màn của Người 5 (bảo hồng - bảo trì). router.dart đã gom sẵn bằng ...maintenanceRoutes.
//
// THỨ TỰ RẤT QUAN TRỌNG: mọi đường dẫn có chữ cố định phải đứng trước đường dẫn có :id,
// không thì "cost-report" và "due-alerts" sẽ bị đọc nhầm thành một id.
import 'package:flutter/material.dart';
// go_router: RouteBase, GoRoute, GoRouterState
import 'package:go_router/go_router.dart';

import 'breakdown_detail_screen.dart';
import 'breakdown_list_screen.dart';
import 'cost_report_screen.dart';
import 'due_alerts_screen.dart';
import 'maintenance_detail_screen.dart';
import 'maintenance_edit_screen.dart';
import 'maintenance_list_screen.dart';
import 'maintenance_plan_screen.dart';
import 'my_breakdowns_screen.dart';
import 'report_breakdown_screen.dart';

final maintenanceRoutes = <RouteBase>[
  // M1: tab "Bảo trì" của quản lý, menu_items.dart đã trỏ sẵn path này.
  GoRoute(
    path: '/maintenance',
    builder: (BuildContext context, GoRouterState state) {
      return MaintenanceListScreen();
    },
  ),
  // M2: lập lịch bảo trì. Phải đứng trước /maintenance/:id.
  // Có ?vehicleId= thì chọn sẵn xe, dùng khi bấm "Lập lịch định kỳ" ở màn đền hạn (M4).
  GoRoute(
    path: '/maintenance/new',
    builder: (BuildContext context, GoRouterState state) {
      final String? vehicleId = state.uri.queryParameters['vehicleId'];
      return MaintenanceEditScreen(initialVehicleId: vehicleId);
    },
  ),
  // M6: báo cáo chi phí. Phải đứng trước /maintenance/:id.
  GoRoute(
    path: '/maintenance/cost-report',
    builder: (BuildContext context, GoRouterState state) {
      return CostReportScreen();
    },
  ),
  // M4: danh sách xe đến hạn. Phải đứng trước /maintenance/:id.
  GoRoute(
    path: '/maintenance/due-alerts',
    builder: (BuildContext context, GoRouterState state) {
      return const DueAlertsScreen();
    },
  ),
  // Q1: danh sách bảo hồng của công ty.
  GoRoute(
    path: '/maintenance/breakdowns',
    builder: (BuildContext context, GoRouterState state) {
      return const BreakdownListScreen();
    },
  ),
  // T6: tài xế báo hồng xe. Đường dẫn này là HỢP ĐỒNG với người 2 (mục "các chuyến màn phải
  // thông nhất sớm" trong tài liệu phân công): màn chi tiết chuyến của tài xế sang màn báo hồng.
  // Người 2 chỉ cần bấm context.push('/driver/trips/$tripId/breakdown').
  GoRoute(
    path: '/driver/trips/:tripId/breakdown',
    builder: (BuildContext context, GoRouterState state) {
      final String tripId = state.pathParameters['tripId']!;
      return ReportBreakdownScreen(tripId: tripId);
    },
  ),
  // M5: định mức bảo trì của một xe. Phải đứng trước /maintenance/:id/edit.
  GoRoute(
    path: '/maintenance/plan/:vehicleId',
    builder: (BuildContext context, GoRouterState state) {
      final String vehicleId = state.pathParameters['vehicleId']!;
      return MaintenancePlanScreen(vehicleId: vehicleId);
    },
  ),
  // Q1: xử lý một bảo hồng. Phải đứng sau /maintenance/breakdowns.
  GoRoute(
    path: '/maintenance/breakdowns/:id',
    builder: (BuildContext context, GoRouterState state) {
      final String id = state.pathParameters['id']!;
      return BreakdownDetailScreen(reportId: id);
    },
  ),
  // M2: sửa lịch (chỉ khi lịch còn "Đã lên lịch").
  GoRoute(
    path: '/maintenance/:id/edit',
    builder: (BuildContext context, GoRouterState state) {
      final String id = state.pathParameters['id']!;
      return MaintenanceEditScreen(recordId: id);
    },
  ),
  // M3: hoàn thành / hủy / sửa chi phí một lịch.
  GoRoute(
    path: '/maintenance/:id',
    builder: (BuildContext context, GoRouterState state) {
      final String id = state.pathParameters['id']!;
      return MaintenanceDetailScreen(recordId: id);
    },
  ),
  // T6: bắt đầu báo hồng mà chưa chọn chuyến. Mở danh sách chuyến để tài xế chọn.
  // Lối này để tài xế tự tạo báo khi quên mở từ chi tiết chuyến.
  GoRoute(
    path: '/driver/breakdowns/new',
    builder: (BuildContext context, GoRouterState state) {
      return const ReportBreakdownScreen(tripId: '');
    },
  ),
  // T6: tab "Báo hỏng" của tài xế (menu_items.dart đã trỏ sẵn path này).
  GoRoute(
    path: '/driver/breakdowns',
    builder: (BuildContext context, GoRouterState state) {
      return const MyBreakdownsScreen();
    },
  ),
];