// Trang chủ: việc gấp lên đầu, vòng tỉ lệ xe, che số tiền, phím tắt theo quyền
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liftmate_mobile/core/i18n.dart';
import 'package:liftmate_mobile/core/session.dart';
import 'package:liftmate_mobile/features/auth/session_provider.dart';
import 'package:liftmate_mobile/features/dashboard/appearance_screen.dart';
import 'package:liftmate_mobile/features/dashboard/bing_wallpaper.dart';
import 'package:liftmate_mobile/features/dashboard/dashboard_api.dart';
import 'package:liftmate_mobile/features/dashboard/dashboard_screen.dart';
import 'package:liftmate_mobile/features/dashboard/home_cover.dart';
import 'package:liftmate_mobile/features/dashboard/home_tasks.dart';

Map<String, dynamic> alert(String plate, int days, {String? blocks}) => <String, dynamic>{
      'vehiclePublicId': plate,
      'plateNumber': plate,
      'documentType': 'VehicleInspection',
      'effectiveUntil': '2026-11-01T00:00:00Z',
      'daysRemaining': days,
      'urgency': 'x',
      'blocksCapability': blocks,
    };

DashboardSummary summaryOf({List<Map<String, dynamic>> alerts = const <Map<String, dynamic>>[], int finalize = 0, int invoice = 0, Map<String, dynamic>? fleet, bool finance = false}) {
  return DashboardSummary.fromJson(<String, dynamic>{
    'fleet': fleet ?? <String, dynamic>{'totalVehicles': 20, 'availableCount': 12, 'inUseCount': 5, 'maintenanceCount': 2, 'suspendedCount': 0, 'notRoadworthyCount': 1, 'readinessRatePercent': 60, 'utilizationThisMonthPercent': 64},
    'today': <String, dynamic>{'tripsToday': 6, 'vehiclesOnTripNow': 5, 'crewWorkingToday': 9},
    'orders': <String, dynamic>{'activeOrdersCount': 8, 'awaitingFinalizationCount': finalize, 'awaitingInvoiceCount': invoice},
    'finance': finance
        ? <String, dynamic>{'revenueThisMonth': 412000000, 'awaitingFinalizationAmount': 62000000, 'awaitingInvoiceAmount': 1000, 'maintenanceCostThisMonth': 18500000}
        : null,
    'urgentAlerts': alerts,
  });
}

class FakeSession extends SessionNotifier {
  final List<String> permissions;

  FakeSession(this.permissions);

  @override
  Future<Session?> build() async => Session.fromJson(<String, dynamic>{
        'publicId': 'u1',
        'fullName': 'Hoàng Anh',
        'role': 'CompanyAdmin',
        'permissions': permissions,
        'mustChangePassword': false,
        'company': <String, dynamic>{'companyName': 'Nhà xe Demo'},
      });
}

Future<void> pumpHome(WidgetTester tester, List<String> permissions, DashboardSummary? summary) async {
  tester.view.physicalSize = const Size(440 * 3, 2200 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final ProviderContainer container = ProviderContainer(
    overrides: <dynamic>[
      sessionProvider.overrideWith(() => FakeSession(permissions)),
      if (summary != null) dashboardSummaryProvider.overrideWith((Ref ref) async => summary),
    ].cast(),
  );
  addTearDown(container.dispose);
  await tester.runAsync(() => container.read(sessionProvider.future));
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: DashboardScreen())));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() {
    I18n.useStrings(<String, String>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('Thứ tự việc: hết hạn, sắp chặn xe, đơn chờ chốt, chờ hóa đơn, rồi giấy còn lại', () {
    final List<HomeTask> tasks = homeTasks(summaryOf(
      finalize: 2,
      invoice: 3,
      alerts: <Map<String, dynamic>>[alert('sau', 6), alert('chan', 2, blocks: 'Roadworthy'), alert('het', -4), alert('thuong', 2), alert('chanxa', 9, blocks: 'Roadworthy')],
    ));
    expect(
      tasks.map((HomeTask task) => task.alert?.plateNumber ?? task.kind.name).toList(),
      <String>['het', 'chan', 'finalize', 'invoice', 'thuong', 'sau', 'chanxa'],
    );
  });

  test('Không có đơn chờ thì không có dòng đơn', () {
    expect(homeTasks(summaryOf()), isEmpty);
  });

  test('Vòng tỉ lệ: ưu tiên số server, thiếu thì tự tính, không có xe thì null, không vượt 1', () {
    expect(fleetReadiness(summaryOf()), 0.6);
    expect(fleetReadiness(summaryOf(fleet: <String, dynamic>{'totalVehicles': 4, 'availableCount': 1})), 0.25);
    expect(fleetReadiness(summaryOf(fleet: <String, dynamic>{'totalVehicles': 0})), isNull);
    expect(fleetReadiness(summaryOf(fleet: <String, dynamic>{'totalVehicles': 4, 'readinessRatePercent': 130})), 1);
  });

  testWidgets('Ba con số chính; không có việc thì báo mọi thứ ổn', (WidgetTester tester) async {
    await pumpHome(tester, <String>['Reports.ViewOperations', 'Orders.View', 'Vehicles.View'], summaryOf());
    expect(find.text('12'), findsWidgets);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('home.allGood'), findsOneWidget);
    expect(find.text('home.moneyMonth'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Che số tiền rồi hiện lại; lựa chọn được lưu', (WidgetTester tester) async {
    await pumpHome(tester, <String>['Reports.ViewOperations', 'Reports.ViewFinance'], summaryOf(finance: true));
    expect(find.text('412.000.000 đ'), findsOneWidget);
    await tester.tap(find.byIcon(CupertinoIcons.eye_fill));
    await tester.pump();
    expect(find.text('412.000.000 đ'), findsNothing);
    expect(find.text('••••••'), findsWidgets);
    await tester.runAsync(() async {
      expect(await const FlutterSecureStorage().read(key: 'home_hide_money'), '1');
    });
    await tester.tap(find.byIcon(CupertinoIcons.eye_slash_fill));
    await tester.pump();
    expect(find.text('412.000.000 đ'), findsOneWidget);
  });

  testWidgets('Phím tắt theo quyền', (WidgetTester tester) async {
    await pumpHome(tester, <String>['Reports.ViewOperations'], summaryOf());
    expect(find.text('home.createOrder'), findsNothing);
    expect(find.text('home.revenue'), findsNothing);
    expect(find.text('home.documents'), findsOneWidget);
  });

  testWidgets('Chỉ có quyền tài chính: không gọi summary, vẫn vào được Doanh thu', (WidgetTester tester) async {
    await pumpHome(tester, <String>['Reports.ViewFinance'], null);
    expect(find.text('home.revenue'), findsWidgets);
    expect(find.text('home.tripsToday'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('Ảnh Bing', () {
    Map<String, dynamic> reply(Object? urlBase, {Object? date = '20261101'}) => <String, dynamic>{
          'images': <dynamic>[
            <String, dynamic>{'startdate': date, 'urlbase': urlBase, 'copyright': 'Black Forest (© Getty Images)'},
          ],
        };

    test('Đọc đúng ảnh và ghi công', () {
      final BingImage image = BingImage.parse(reply('/th?id=OHR.SchwarzwaldAutumn_ROW3364796116'))!;
      expect(image.url.toString(), 'https://www.bing.com/th?id=OHR.SchwarzwaldAutumn_ROW3364796116_1920x1080.jpg');
      expect(image.startDate, '20261101');
      expect(image.copyright, contains('Getty'));
    });

    test('Giờ đổi ảnh kế tiếp: giờ bắt đầu theo UTC cộng 24 giờ, sang tháng vẫn đúng; thiếu hoặc lạ thì null', () {
      Map<String, dynamic> withStart(Object? start) => <String, dynamic>{
            'images': <dynamic>[
              <String, dynamic>{'startdate': '20261102', 'urlbase': '/th?id=A', 'copyright': '', 'fullstartdate': start},
            ],
          };
      expect(BingImage.parse(withStart('202611020800'))!.nextChangeAt, DateTime.utc(2026, 11, 3, 8));
      expect(BingImage.parse(withStart('202611300800'))!.nextChangeAt, DateTime.utc(2026, 12, 1, 8));
      expect(BingImage.parse(withStart(null))!.nextChangeAt, isNull);
      expect(BingImage.parse(withStart('hom-nay'))!.nextChangeAt, isNull);
    });

    test('Khi nào hỏi lại Bing', () {
      final DateTime change = DateTime.utc(2026, 11, 3, 8);
      final DateTime checked = DateTime.utc(2026, 11, 2, 22);
      // Tải sáng sớm, trước giờ đổi: chưa hỏi
      expect(shouldCheckBing(now: change.subtract(const Duration(minutes: 1)), nextChangeAt: change, lastCheckedAt: checked), isFalse);
      // Qua giờ đổi: hỏi ngay, không đợi sang ngày mới (lỗi cũ)
      expect(shouldCheckBing(now: change, nextChangeAt: change, lastCheckedAt: checked), isTrue);
      // Bing chưa đổi kịp: cách 15 phút mới hỏi lại
      final DateTime justChecked = change.add(const Duration(minutes: 1));
      expect(shouldCheckBing(now: change.add(const Duration(minutes: 10)), nextChangeAt: change, lastCheckedAt: justChecked), isFalse);
      expect(shouldCheckBing(now: change.add(const Duration(minutes: 16)), nextChangeAt: change, lastCheckedAt: justChecked), isTrue);
      // Bản cũ chưa lưu giờ đổi: hỏi ngay
      expect(shouldCheckBing(now: checked, nextChangeAt: null, lastCheckedAt: null), isTrue);
      // Đồng hồ máy sai: không tin giờ đổi quá xa, không kẹt ảnh cũ mãi
      expect(shouldCheckBing(now: checked, nextChangeAt: checked.add(const Duration(days: 30)), lastCheckedAt: null), isTrue);
      expect(shouldCheckBing(now: checked, nextChangeAt: null, lastCheckedAt: checked.add(const Duration(days: 30))), isTrue);
    });

    test('Dữ liệu lạ hoặc địa chỉ ngoài đường dẫn ảnh Bing thì bỏ', () {
      expect(BingImage.parse(null), isNull);
      expect(BingImage.parse(<String, dynamic>{'images': <dynamic>[]}), isNull);
      expect(BingImage.parse(reply('https://evil.example/a.jpg')), isNull);
      expect(BingImage.parse(reply('//evil.example/th?id=A')), isNull);
      expect(BingImage.parse(reply('/th?id=A&x=../..')), isNull);
      expect(BingImage.parse(reply('/th?id=A', date: 'hom-nay')), isNull);
    });
  });

  testWidgets('Trang chủ có nút Cài đặt giao diện ở cuối', (WidgetTester tester) async {
    await pumpHome(tester, <String>['Reports.ViewOperations'], summaryOf());
    expect(find.text('home.appearance'), findsOneWidget);
  });

  testWidgets('Màn Cài đặt giao diện: ba lựa chọn, mới vào là Mặc định, chọn Mặc định không lỗi', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(440 * 3, 956 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final ProviderContainer container = ProviderContainer(overrides: <dynamic>[sessionProvider.overrideWith(() => FakeSession(<String>[]))].cast());
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(sessionProvider.future));
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: AppearanceScreen())));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(find.text('appearance.standard'), findsOneWidget);
    expect(find.text('appearance.bing'), findsOneWidget);
    expect(find.text('appearance.custom'), findsOneWidget);
    expect(find.text('appearance.standardNote'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.checkmark_alt), findsOneWidget);
    await tester.tap(find.text('appearance.standard'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ảnh bìa mặc định vẽ được cả sáng lẫn tối', (WidgetTester tester) async {
    for (final bool dark in <bool>[false, true]) {
      await tester.pumpWidget(SizedBox(width: 440, height: 400, child: CustomPaint(painter: DefaultCoverPainter(dark: dark))));
      expect(tester.takeException(), isNull);
    }
  });
}
