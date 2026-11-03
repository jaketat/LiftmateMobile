// Sửa đơn đã lưu chỉ gửi phần đổi và không làm mất ô app không có. Bản đồ tĩnh canh đủ điểm. Nháp thiếu thì nằm trên máy.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liftmate_mobile/core/i18n.dart';
import 'package:liftmate_mobile/core/session.dart';
import 'package:liftmate_mobile/features/orders/order_draft_store.dart';
import 'package:liftmate_mobile/features/orders/order_edit.dart';
import 'package:liftmate_mobile/features/orders/order_form.dart';
import 'package:liftmate_mobile/features/orders/order_new_screen.dart';
import 'package:liftmate_mobile/features/orders/orders_api.dart';
import 'package:liftmate_mobile/features/orders/static_map.dart';
import 'package:liftmate_mobile/features/orders/stop_location_screen.dart';
import 'package:vietmap_flutter_gl/vietmap_flutter_gl.dart' show LatLng;

OrderDetail sampleOrder({String status = 'Draft'}) {
  return OrderDetail.fromJson(<String, dynamic>{
    'publicId': 'o1',
    'orderCode': 'DH-1',
    'customer': <String, dynamic>{'publicId': 'c1', 'customerName': 'Thép', 'phone': '0900000001'},
    'status': status,
    'allowedActions': <String>['sendQuote', 'cancel'],
    'operatingProfile': 'MultiDrop',
    'estimationVehicle': <String, dynamic>{'publicId': 'v1'},
    'estimationTractor': <String, dynamic>{'publicId': 'v2'},
    'quotedAmount': 1500000,
    'notes': 'Ghi chú',
    'createdAt': '2026-10-01T03:00:00Z',
    'stops': <Map<String, dynamic>>[
      <String, dynamic>{'sequence': 1, 'kind': 'Pickup', 'address': 'A', 'latitude': 21.0, 'longitude': 105.8},
      <String, dynamic>{'sequence': 2, 'kind': 'Delivery', 'address': 'B', 'latitude': 20.9, 'longitude': 106.0, 'unloadMethod': 'ForkliftFromRear'},
    ],
    'workDays': <Map<String, dynamic>>[
      <String, dynamic>{'workDate': '2026-11-10', 'startTime': '08:00:00', 'endTime': '17:30:00'},
    ],
    'cargos': <Map<String, dynamic>>[
      <String, dynamic>{
        'publicId': 'k1',
        'cargoName': 'Máy tiện',
        'quantity': 2,
        'weightKg': 1200,
        'lengthMm': 2000,
        'widthMm': 1000,
        'heightMm': 1500,
        'rotationAllowed': false,
        'supportType': 'Flat',
        'readyDate': '2026-11-09',
        'pickupStopSequence': 1,
        'dropStopSequence': 2,
      },
    ],
  });
}

class Dispatcher {
  static Session make(List<String> permissions) {
    return Session(fullName: 'An', companyName: 'LM', roleName: 'DP', permissions: permissions, mustChangePassword: false);
  }
}

void main() {
  setUp(() {
    I18n.useStrings(<String, String>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  group('sửa đơn', () {
    test('mở đơn lên form giữ đủ dữ liệu, chưa sửa gì thì không có gì để gửi', () {
      final OrderDetail order = sampleOrder();
      final OrderFormData form = OrderFormData.fromOrder(order);
      expect(form.customerId, 'c1');
      expect(form.stops.last.unloadMethod, 'ForkliftFromRear');
      expect(form.workDays.single.endTime, '17:30');
      expect(form.operatingProfile, 'MultiDrop');
      expect(form.cargos.single.rotationAllowed, isFalse);
      expect(orderEditChanges(form, OrderEditBaseline.of(form)).isEmpty, isTrue);
    });

    test('chỉ sửa giá thì chỉ gửi lệnh đơn, và không làm mất xe ước tính', () {
      final OrderDetail order = sampleOrder();
      final OrderFormData form = OrderFormData.fromOrder(order);
      final OrderEditBaseline baseline = OrderEditBaseline.of(form);
      form.quotedAmount = 2000000;
      final OrderEditChanges changes = orderEditChanges(form, baseline);
      expect(changes.order, isTrue);
      expect(changes.workDays, isFalse);
      expect(changes.changedCargos, isEmpty);
      final Map<String, dynamic> body = orderUpdateBody(form);
      expect(body['estimationVehiclePublicId'], 'v1');
      expect(body['estimationTractorPublicId'], 'v2');
    });

    test('sửa kiện giữ nguyên các ô app không có', () {
      final OrderDetail order = sampleOrder();
      final OrderFormData form = OrderFormData.fromOrder(order);
      final OrderEditBaseline baseline = OrderEditBaseline.of(form);
      form.cargos.single.quantity = '3';
      final OrderEditChanges changes = orderEditChanges(form, baseline);
      expect(changes.changedCargos.single.serverId, 'k1');
      final Map<String, dynamic> body = changes.changedCargos.single.toUpdateJson();
      expect(body['quantity'], 3);
      expect(body['readyDate'], '2026-11-09');
      expect(body['pickupStopSequence'], 1);
      expect(body['rotationAllowed'], isFalse);
    });

    test('kiện bị xóa và kiện mới được tách riêng', () {
      final OrderDetail order = sampleOrder();
      final OrderFormData form = OrderFormData.fromOrder(order);
      final OrderEditBaseline baseline = OrderEditBaseline.of(form);
      form.cargos
        ..clear()
        ..add(CargoDraft(cargoName: 'Mới', weightKg: '1', lengthMm: '1', widthMm: '1', heightMm: '1'));
      final OrderEditChanges changes = orderEditChanges(form, baseline);
      expect(changes.removedCargos, <String>['k1']);
      expect(changes.newCargos.single.cargoName, 'Mới');
      expect(changes.changedCargos, isEmpty);
    });

    test('luật sửa theo web: bước khóa thì gửi đề nghị, có quyền sửa mọi bước thì sửa được cả đơn Đã chốt', () {
      final Session editor = Dispatcher.make(<String>['Orders.Edit']);
      final Session director = Dispatcher.make(<String>['Orders.Edit', 'Orders.EditAnyStage']);
      expect(canEditOrder('Draft', editor), isTrue);
      expect(canEditOrder('Quoted', editor), isTrue);
      expect(canEditOrder('Scheduled', editor), isFalse);
      expect(mustRequestEdit('Scheduled', editor), isTrue);
      expect(mustRequestEdit('Finalized', editor), isFalse);
      expect(canEditOrder('Scheduled', director), isTrue);
      expect(canEditOrder('Finalized', director), isTrue);
      expect(mustRequestEdit('Scheduled', director), isFalse);
      expect(canEditOrder('Invoiced', director), isFalse);
      expect(canEditOrder('Cancelled', director), isFalse);
      expect(canEditOrder('Draft', null), isFalse);
      // Ngày làm sửa thẳng được tới Đã chốt lịch, sau đó mới phải đề nghị
      expect(canEditWorkDays('Scheduled', editor), isTrue);
      expect(mustRequestWorkDays('InProgress', editor), isTrue);
    });

    test('kiện giữ đủ thẻ hàng nặng khi mở lên form và khi gửi lại', () {
      final OrderDetail order = sampleOrder();
      final CargoDraft cargo = OrderFormData.fromOrder(order).cargos.single;
      expect(cargo.pickupStopSequence, 1);
      expect(cargo.dropStopSequence, 2);
      expect(cargo.readyDate, '2026-11-09');
      cargo
        ..travelGroup = ' TRAM-1 '
        ..deliveryWave = '2'
        ..dimensionsSource = 'Measured'
        ..cogOffsetXMm = '-120';
      final Map<String, dynamic> body = cargo.toJson();
      expect(body['travelGroup'], 'TRAM-1');
      expect(body['deliveryWave'], 2);
      expect(body['dimensionsSource'], 'Measured');
      expect(body['cogOffsetXMm'], -120);
      expect(body['readyDate'], '2026-11-09');
      expect(cargo.toUpdateJson()['deliveryWave'], 2);
      cargo.deliveryWave = '100';
      expect(cargo.validate()['deliveryWave'], isNotNull);
    });
  });

  group('điểm dừng theo web', () {
    OrderFormData threeStops() {
      return OrderFormData()
        ..stops = <StopDraft>[StopDraft(kind: 'Pickup', address: 'A'), StopDraft(kind: 'Pickup', address: 'B'), StopDraft(kind: 'Delivery', address: 'C')]
        ..cargos = <CargoDraft>[CargoDraft(pickupStopSequence: 2, dropStopSequence: 3)];
    }

    test('chỗ chèn điểm mới: bốc sau điểm đầu, đi qua trước điểm cuối, trả xuống cuối', () {
      final OrderFormData form = threeStops();
      expect(form.insertIndexFor('Pickup'), 1);
      expect(form.insertIndexFor('Via'), 2);
      expect(form.insertIndexFor('Delivery'), 3);
    });

    test('đổi thứ tự thì kiện vẫn trỏ đúng điểm', () {
      final OrderFormData form = threeStops();
      form.changeStops(() => form.stops.insert(0, form.stops.removeAt(1)));
      expect(form.cargos.single.pickupStopSequence, 1);
      expect(form.cargos.single.dropStopSequence, 3);
    });

    test('xóa điểm hoặc đổi loại điểm thì kiện về chưa chọn', () {
      final OrderFormData form = threeStops();
      form.changeStops(() => form.stops.removeAt(1));
      expect(form.cargos.single.pickupStopSequence, isNull);
      expect(form.cargos.single.dropStopSequence, 2);
      form.changeStops(() => form.stops.last.kind = 'Via');
      expect(form.cargos.single.dropStopSequence, isNull);
    });

    test('xe dự kiến đi vào ước tính tuyến, tạo đơn và sửa đơn', () {
      final OrderFormData form = OrderFormData()
        ..stops = <StopDraft>[StopDraft(kind: 'Pickup', latitude: 21, longitude: 105), StopDraft(kind: 'Delivery', latitude: 20, longitude: 106)]
        ..estimationVehicleId = 'v1'
        ..estimationTractorId = 'v2';
      expect(form.routeRequest()!['estimationVehiclePublicId'], 'v1');
      expect(form.routeRequest()!['estimationTractorPublicId'], 'v2');
      expect(form.toJson()['estimationVehiclePublicId'], 'v1');
      expect(orderUpdateBody(form)['estimationTractorPublicId'], 'v2');
    });

    test('ước tính đọc đủ số liệu như web', () {
      final RouteEstimate route = RouteEstimate.fromJson(<String, dynamic>{
        'distanceKm': 1346.1,
        'durationMinutes': 975,
        'tollCost': 4129000,
        'tollVehicleClass': 5,
        'tollClassAssumed': true,
        'routeExpressways': <String>['Cao Tốc Vân Phong Nha Trang'],
      });
      expect(route.durationMinutes, 975);
      expect(route.tollVehicleClass, 5);
      expect(RouteEstimate.fromJson(route.toJson()).expressways.single, 'Cao Tốc Vân Phong Nha Trang');
    });
  });

  group('bản đồ', () {
    test('canh khung: mọi điểm nằm trong khung và trong lề', () {
      final List<LatLng> points = <LatLng>[LatLng(21.03, 105.85), LatLng(20.65, 106.05), LatLng(20.9, 105.6)];
      const Size size = Size(400, 190);
      const double pad = 36;
      final StaticMapView view = fitStaticMap(points, size, const EdgeInsets.all(pad));
      for (final LatLng point in points) {
        final Offset at = view.project(point);
        expect(at.dx, inInclusiveRange(pad - 1, size.width - pad + 1));
        expect(at.dy, inInclusiveRange(pad - 1, size.height - pad + 1));
      }
    });

    test('một điểm thì phóng gần và đặt giữa khung', () {
      const Size size = Size(400, 130);
      final StaticMapView view = fitStaticMap(<LatLng>[LatLng(21.0, 105.8)], size, const EdgeInsets.all(36));
      expect(view.zoom, 15);
      final Offset at = view.project(LatLng(21.0, 105.8));
      expect(at.dx, closeTo(200, 0.01));
      expect(at.dy, closeTo(65, 0.01));
    });

    test('ghép địa chỉ bỏ ô trống và ô trùng', () {
      expect(formatPlacemark(<String?>['12 Lê Lợi', 'Lê Lợi', null, 'Bến Nghé', '', 'Hồ Chí Minh']), '12 Lê Lợi, Bến Nghé, Hồ Chí Minh');
    });

    test('tuyến ước tính giữ đường vẽ qua lưu nháp', () {
      final RouteEstimate route = RouteEstimate.fromJson(<String, dynamic>{'distanceKm': 5, 'polyline': 'abc'});
      expect(RouteEstimate.fromJson(route.toJson()).polyline, 'abc');
    });
  });

  group('lưu nháp', () {
    Future<GoRouter> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1320, 2868);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final GoRouter router = GoRouter(
        initialLocation: '/start',
        routes: <RouteBase>[
          GoRoute(path: '/start', builder: (BuildContext context, GoRouterState state) => const Scaffold(body: Text('danh sách'))),
          GoRoute(path: '/new', builder: (BuildContext context, GoRouterState state) => const OrderNewScreen()),
        ],
      );
      await tester.pumpWidget(ProviderScope(child: MaterialApp.router(routerConfig: router)));
      router.push('/new');
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('form trống bấm Lưu nháp thì thoát, không báo lỗi đỏ', (WidgetTester tester) async {
      await pump(tester);
      expect(find.text('orderForm.saveDraft'), findsOneWidget);
      await tester.tap(find.text('orderForm.saveDraft'));
      await tester.pumpAndSettle();
      expect(find.text('danh sách'), findsOneWidget);
      expect(find.text('orderForm.errorCustomer'), findsNothing);
    });

    testWidgets('gửi báo giá khi thiếu thì vẫn ở lại và báo lỗi', (WidgetTester tester) async {
      await pump(tester);
      await tester.tap(find.text('orderForm.saveAndQuote'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('orderForm.errorCustomer'), findsOneWidget);
      expect(find.text('danh sách'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('kéo đổi thứ tự: điểm đổi chỗ, sai thứ tự thì báo ngay nhưng vẫn lưu nháp được', (WidgetTester tester) async {
      await pump(tester);
      double top(String label) => tester.getTopLeft(find.text(label)).dy;
      expect(top('labels.stopKind.Pickup'), lessThan(top('labels.stopKind.Delivery · orderForm.unloadCrane')));
      expect(find.text('orderForm.errorFirstPickup'), findsNothing);

      final Offset handle = tester.getCenter(find.byIcon(CupertinoIcons.line_horizontal_3).first);
      final TestGesture gesture = await tester.startGesture(handle);
      await tester.pump(const Duration(milliseconds: 50));
      for (int step = 0; step < 6; step++) {
        await gesture.moveBy(const Offset(0, 30));
        await tester.pump(const Duration(milliseconds: 80));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(top('labels.stopKind.Delivery · orderForm.unloadCrane'), lessThan(top('labels.stopKind.Pickup')));
      expect(find.text('orderForm.errorFirstPickup'), findsOneWidget);

      await tester.tap(find.text('orderForm.saveDraft'));
      await tester.pumpAndSettle();
      expect(find.text('danh sách'), findsOneWidget);
    });

    test('thứ tự điểm: đầu phải là điểm bốc, cuối không được là điểm đi qua', () {
      final OrderFormData form = OrderFormData();
      expect(form.stopOrderError, isNull);
      form.stops = <StopDraft>[StopDraft(kind: 'Delivery'), StopDraft(kind: 'Pickup')];
      expect(form.stopOrderError, 'orderForm.errorFirstPickup');
      form.stops = <StopDraft>[StopDraft(kind: 'Pickup'), StopDraft(kind: 'Delivery'), StopDraft(kind: 'Via')];
      expect(form.stopOrderError, 'orderForm.errorLastVia');
    });

    test('bản nháp chưa đủ vẫn đọc lại được', () async {
      final OrderFormData form = OrderFormData()..notes = 'dở dang';
      final SavedOrderDraft draft = SavedOrderDraft(form: form, idempotencyKey: 'k', quotedText: '');
      await OrderDraftStore.save('u1', draft.encodeBody());
      expect((await OrderDraftStore.load('u1'))?.form.notes, 'dở dang');
    });
  });
}
