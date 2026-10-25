import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liftmate_mobile/core/session.dart';
import 'package:liftmate_mobile/features/auth/session_provider.dart';
import 'package:liftmate_mobile/features/customers/customer_detail_screen.dart';
import 'package:liftmate_mobile/features/customers/customers_api.dart';
import 'package:liftmate_mobile/features/dashboard/alerts_screen.dart';
import 'package:liftmate_mobile/features/dashboard/dashboard_api.dart';
import 'package:liftmate_mobile/features/dashboard/dashboard_screen.dart';
import 'package:liftmate_mobile/features/dashboard/revenue_screen.dart';
import 'package:liftmate_mobile/features/fleet/fleet_api.dart';
import 'package:liftmate_mobile/features/fleet/shared.dart';
import 'package:liftmate_mobile/features/fleet/vehicle_detail_screen.dart';
import 'package:liftmate_mobile/features/staff/staff_api.dart';
import 'package:liftmate_mobile/features/staff/staff_detail_screen.dart';

class FakeSession extends SessionNotifier {
  @override
  Future<Session?> build() async {
    return Session(
      fullName: 'Giám đốc Demo',
      companyName: 'Nhà xe Demo',
      roleName: 'Giám đốc',
      permissions: const <String>[
        'Vehicles.View', 'Vehicles.Edit', 'Users.View', 'Users.ManageRoles', 'Users.ManageComplianceDocs',
        'Reports.ViewOperations', 'Reports.ViewFinance', 'Customers.View', 'Customers.Create', 'Orders.View',
      ],
      mustChangePassword: false,
    );
  }
}

final Map<String, dynamic> vehicleJson = <String, dynamic>{
  'publicId': 'v1', 'plateNumber': '51C-900.01', 'manufacturerSerialNumber': null, 'baseType': 'Truck',
  'vehicleType': 'Xe tải 3 chân', 'brand': 'Hino', 'model': 'FL', 'manufactureYear': 2021, 'curbWeightKg': 9800.5,
  'maxPayloadKg': 15000, 'currentEngineHours': 3420, 'status': 'Available', 'inspectionExpiryDate': '2027-03-12T00:00:00Z',
  'isInspectionValid': true, 'insuranceExpiryDate': null, 'inspectionCertificateNumber': 'KD-1', 'deckLengthMm': 9400,
  'deckWidthMm': 2450, 'fuelConsumptionPer100Km': 28,
  'capacityWarnings': <dynamic>[<String, dynamic>{'code': 'X', 'message': 'Chưa khai vệt bánh sau.'}],
  'recentMaintenance': <dynamic>[<String, dynamic>{'title': 'Thay dầu', 'kind': 'Periodic', 'status': 'Completed', 'startDate': '2026-09-02', 'completedOn': '2026-09-02'}],
};

final Map<String, dynamic> docJson = <String, dynamic>{
  'publicId': 'd1', 'documentType': 'VehicleInspection', 'documentNumber': 'A1', 'issuedBy': null, 'issuedAt': null,
  'effectiveUntil': DateTime.now().add(const Duration(days: 2)).toUtc().toIso8601String(), 'blocksCapability': 'Roadworthy',
  'fileUrl': null, 'createdAt': '2026-01-01T00:00:00Z', 'isVoided': false, 'voidReason': null,
};

final Map<String, dynamic> alertJson = <String, dynamic>{
  'vehiclePublicId': 'v1', 'plateNumber': '51C-900.09', 'baseType': 'Truck', 'brand': null, 'model': null,
  'documentType': 'VehicleInspection', 'documentNumber': null, 'effectiveUntil': '2026-10-10T00:00:00Z',
  'daysRemaining': -6, 'urgency': 'Expired', 'blocksCapability': 'Roadworthy', 'vehicleStatus': 'Suspended',
};

Future<void> pump(WidgetTester tester, Widget screen, List overrides) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: <dynamic>[sessionProvider.overrideWith(FakeSession.new), ...overrides].cast(),
    child: MaterialApp(home: screen),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('nhãn hạn giấy tờ', () {
    expect(daysPill(-6).text, 'Hết hạn 6 ngày');
    expect(daysPill(0).text, 'Hết hạn hôm nay');
    expect(daysPill(2).foreground, daysPill(-1).foreground);
    expect(daysPill(6).text, 'Còn 6 ngày');
    expect(daysPill(30).text, 'Còn hạn');
    expect(formatDay('2027-03-12T00:00:00Z'), '12/03/2027');
  });

  testWidgets('X2 chi tiết xe', (WidgetTester tester) async {
    await pump(tester, const VehicleDetailScreen(vehicleId: 'v1'), [
      vehicleProvider('v1').overrideWith((ref) async => VehicleDetail.fromJson(vehicleJson)),
      vehicleOdometerProvider('v1').overrideWith((ref) async => 128450),
      vehicleDocsProvider('v1').overrideWith((ref) async => parseDocs(<dynamic>[docJson])),
    ]);
    expect(find.text('128.450 km'), findsOneWidget);
    expect(find.text('Chưa khai vệt bánh sau.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Còn 2 ngày'), 200);
    expect(find.text('Còn 2 ngày'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Thay dầu'), 200);
    expect(find.text('Thay dầu'), findsOneWidget);
  });

  testWidgets('B1 trang chủ, B3 cảnh báo', (WidgetTester tester) async {
    final DashboardSummary summary = DashboardSummary.fromJson(<String, dynamic>{
      'fleet': <String, dynamic>{'totalVehicles': 20, 'availableCount': 11, 'inUseCount': 5, 'maintenanceCount': 2, 'suspendedCount': 1, 'notRoadworthyCount': 1, 'utilizationThisMonthPercent': 64.2},
      'today': <String, dynamic>{'tripsToday': 6, 'vehiclesOnTripNow': 5, 'crewWorkingToday': 9},
      'orders': <String, dynamic>{'activeOrdersCount': 8, 'awaitingFinalizationCount': 2, 'awaitingInvoiceCount': 3},
      'finance': null,
      'urgentAlerts': <dynamic>[alertJson],
    });
    await pump(tester, const DashboardScreen(), [dashboardSummaryProvider.overrideWith((ref) async => summary)]);
    expect(find.text('20 xe · dùng 64% tháng này'), findsOneWidget);
    expect(find.textContaining('Tiền tháng'), findsNothing);
    expect(find.text('Không chạy được'), findsOneWidget);

    await pump(tester, const AlertsScreen(), [
      vehicleAlertsProvider(null).overrideWith((ref) async => parseVehicleAlerts(<dynamic>[alertJson])),
      staffAlertsProvider(null).overrideWith((ref) async => <StaffAlert>[]),
    ]);
    expect(find.text('Xe (1)'), findsOneWidget);
    expect(find.text('Xe không được chạy đến khi gia hạn'), findsOneWidget);
  });

  testWidgets('B2 doanh thu', (WidgetTester tester) async {
    final List<dynamic> months = <dynamic>[];
    for (int m = 1; m <= 12; m++) {
      months.add(<String, dynamic>{'month': m, 'revenue': m * 30000000, 'ordersCount': m, 'estimatedFuelAndTollCost': 1000000, 'maintenanceCost': 500000, 'quotesSent': 1, 'quotesConfirmed': 1});
    }
    final RevenueReport report = RevenueReport.fromJson(<String, dynamic>{
      'year': DateTime.now().year, 'totalRevenueYtd': 3720000000, 'totalRevenueThisMonth': 412000000, 'averageOrderValue': 48000000,
      'estimatedFuelAndTollCostYtd': 1, 'maintenanceCostYtd': 146000000, 'quoteConversionPercent': 62.0,
      'monthlyRevenue': months,
      'topCustomers': <dynamic>[<String, dynamic>{'customerPublicId': 'c', 'customerCode': 'KH', 'customerName': 'Kết cấu Bình An', 'totalSpent': 210000000, 'ordersCount': 3, 'isDeleted': true}],
    });
    await pump(tester, const RevenueScreen(), [revenueProvider(DateTime.now().year).overrideWith((ref) async => report)]);
    expect(find.text('3.720.000.000 đ'), findsOneWidget);
    expect(find.text('62%'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Kết cấu Bình An (đã xóa)'), 200);
  });

  testWidgets('S2 nhân sự, C2 khách', (WidgetTester tester) async {
    final StaffUser user = StaffUser.fromJson(<String, dynamic>{
      'publicId': 'u1', 'username': 'tx1', 'fullName': 'Tài xế 1', 'phone': '0987650004', 'email': null, 'avatarUrl': null,
      'roleName': 'Driver', 'roleId': 'r1', 'isActive': true, 'createdAt': '2026-01-01T00:00:00Z', 'status': 'Active',
      'driverProfile': <String, dynamic>{'licenseNumber': '790123456789', 'licenseClass': 'FC', 'licenseExpiryDate': '2029-08-15', 'licenseImageUrl': null, 'isAvailable': true},
    });
    await pump(tester, const StaffDetailScreen(userId: 'u1'), [
      staffUserProvider('u1').overrideWith((ref) async => user),
      staffDocsProvider('u1').overrideWith((ref) async => null),
    ]);
    expect(find.text('Tài xế · đang làm'), findsOneWidget);
    expect(find.text('FC'), findsOneWidget);
    expect(find.text('Giấy tờ'), findsNothing);
    expect(find.text('Đổi vai trò'), findsOneWidget);

    final CustomerDetail detail = CustomerDetail.fromJson(<String, dynamic>{
      'publicId': 'c1', 'customerCode': 'KH-0003', 'customerName': 'Cơ khí Minh Phát', 'contactPerson': 'Anh Phát', 'phone': '0909123456',
      'email': null, 'address': null, 'taxCode': '0312345678', 'note': null, 'createdAt': 'x', 'updatedAt': null,
      'totalOrdersCount': 14, 'activeOrdersCount': 2, 'totalSpentAmount': null,
    });
    await pump(tester, const CustomerDetailScreen(customerId: 'c1'), [
      customerProvider('c1').overrideWith((ref) async => detail),
      customerOrdersProvider('c1').overrideWith((ref) async => <RecentOrder>[
            RecentOrder(publicId: 'o1', orderCode: 'DH-202610-0012', status: 'Quoted', scheduledDate: '2026-10-20', createdAt: '2026-10-01T00:00:00Z'),
          ]),
    ]);
    expect(find.text('Đã chi'), findsNothing);
    expect(find.text('Email'), findsNothing);
    expect(find.text('DH-202610-0012 · 20/10/2026'), findsOneWidget);
  });
}
