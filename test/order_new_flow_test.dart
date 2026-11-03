// Không mất đơn đang nhập, và không kẹt khi AI làm lâu
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liftmate_mobile/core/api/api_client.dart';
import 'package:liftmate_mobile/core/i18n.dart';
import 'package:liftmate_mobile/core/session.dart';
import 'package:liftmate_mobile/features/auth/session_provider.dart';
import 'package:liftmate_mobile/features/orders/order_ai_screen.dart';
import 'package:liftmate_mobile/features/orders/order_draft_store.dart';
import 'package:liftmate_mobile/features/orders/order_form.dart';
import 'package:liftmate_mobile/features/orders/order_new_screen.dart';

/// Giữ yêu cầu lại tới khi test cho phép trả lời, như AI đang làm lâu
class HeldAdapter implements HttpClientAdapter {
  final Completer<void> release = Completer<void>();
  final List<RequestOptions> requests = <RequestOptions>[];
  Map<String, dynamic> reply = <String, dynamic>{};

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    await release.future;
    return ResponseBody.fromString(
      jsonEncode(<String, dynamic>{'isSuccess': true, 'data': reply}),
      200,
      headers: <String, List<String>>{Headers.contentTypeHeader: <String>[Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

Session fakeSession(Map<String, dynamic> extra) => Session.fromJson(<String, dynamic>{'publicId': 'u1', 'fullName': 'A', 'role': 'CompanyAdmin', 'permissions': <String>[], 'mustChangePassword': false, 'company': <String, dynamic>{'publicId': 'c', 'companyName': 'X', 'name': 'X', 'plan': 'Pro', 'status': 'Active'}, ...extra});

class FakeSession extends SessionNotifier {
  @override
  Future<Session?> build() async => fakeSession(<String, dynamic>{});
}

Future<void> pumpForm(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/new',
          routes: <RouteBase>[
            GoRoute(path: '/', builder: (BuildContext context, GoRouterState state) => const Text('Danh sách')),
            GoRoute(path: '/new', builder: (BuildContext context, GoRouterState state) => const OrderNewScreen()),
          ],
        ),
      ),
    ),
  );
  // Đọc nháp là việc bất đồng bộ thật; trong lúc đó màn có vòng xoay nên chưa settle được
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump();
}

Future<ProviderContainer> loggedIn() async {
  final ProviderContainer container = ProviderContainer(overrides: <dynamic>[sessionProvider.overrideWith(FakeSession.new)].cast());
  await container.read(sessionProvider.future);
  return container;
}

String savedDraftJson() {
  final OrderFormData form = OrderFormData()
    ..customerId = 'c1'
    ..customerName = 'Cảng Hải Phòng'
    ..customerPhone = '0932256272'
    ..notes = 'Ghi chú nháp';
  form.stops.first.address = 'KCN Nam Cầu Kiền';
  return SavedOrderDraft(form: form, idempotencyKey: 'key-cu', quotedText: '1.500.000').encodeBody();
}

void main() {
  setUp(() {
    I18n.useStrings(<String, String>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  group('Tự lưu nháp', () {
    test('Mỗi tài khoản một bản; xóa được; file hỏng thì bỏ chứ không làm sập', () async {
      await OrderDraftStore.save('u1', savedDraftJson());
      expect((await OrderDraftStore.load('u1'))!.form.customerName, 'Cảng Hải Phòng');
      expect((await OrderDraftStore.load('u1'))!.idempotencyKey, 'key-cu');
      expect((await OrderDraftStore.load('u1'))!.savedAt, isNotNull);
      expect(await OrderDraftStore.load('u2'), isNull);

      await OrderDraftStore.clear('u1');
      expect(await OrderDraftStore.load('u1'), isNull);

      FlutterSecureStorage.setMockInitialValues(<String, String>{'order_draft_u1': '{hỏng'});
      expect(await OrderDraftStore.load('u1'), isNull);
    });

    testWidgets('Mở form có nháp thì hiện lại đủ, báo đang tiếp tục, và Làm lại thì xóa nháp', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1320, 2868);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => OrderDraftStore.save('u1', savedDraftJson()));
      final ProviderContainer container = await tester.runAsync(loggedIn) as ProviderContainer;
      addTearDown(container.dispose);
      await pumpForm(tester, container);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      expect(find.text('Cảng Hải Phòng'), findsOneWidget);
      // Đề mục có biểu tượng đi kèm
      expect(find.byIcon(CupertinoIcons.person_fill), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.location_solid), findsOneWidget);
      expect(find.textContaining('KCN Nam Cầu Kiền'), findsOneWidget);
      expect(find.text('orderForm.startOver'), findsOneWidget);

      await tester.tap(find.text('orderForm.startOver'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('orderForm.discard'));
      await tester.pumpAndSettle();

      expect(find.text('Cảng Hải Phòng'), findsNothing);
      expect(find.text('orderForm.startOver'), findsNothing);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(await tester.runAsync(() => OrderDraftStore.load('u1')), isNull);
    });
  });

  group('Huỷ khi AI làm lâu', () {
    late HeldAdapter adapter;
    late HttpClientAdapter original;

    setUp(() {
      original = dio.httpClientAdapter;
      adapter = HeldAdapter();
      dio.httpClientAdapter = adapter;
    });
    tearDown(() => dio.httpClientAdapter = original);

    Future<void> pasteAndParse(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1320, 2868);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: OrderAiScreen(thenOpenForm: false)));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('orderAi.pasteInstead'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(EditableText), '2 máy tiện CNC 6 tấn 5');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('orderAi.parse'));
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('Bấm Huỷ thì hết chờ ngay, giữ chữ đã dán, làm lại được', (WidgetTester tester) async {
      await pasteAndParse(tester);
      expect(find.text('orderAi.parsing'), findsOneWidget);
      expect(find.text('orderAi.parse'), findsNothing);

      await tester.tap(find.text('common.cancel'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('orderAi.parsing'), findsNothing);
      expect(find.text('orderAi.parse'), findsOneWidget);
      expect(find.text('2 máy tiện CNC 6 tấn 5'), findsOneWidget);
      // Không báo lỗi mạng cho việc người dùng tự huỷ
      expect(find.text('api.noConnection'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('Kết quả về muộn sau khi Huỷ bị bỏ qua', (WidgetTester tester) async {
      await pasteAndParse(tester);
      await tester.tap(find.text('common.cancel'));
      await tester.pump(const Duration(milliseconds: 100));

      adapter.reply = <String, dynamic>{'cargos': <dynamic>[], 'warnings': <dynamic>[]};
      adapter.release.complete();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('orderAi.parse'), findsOneWidget);
      expect(find.text('orderAi.resultsTitle'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('Bấm nút quay lại lúc AI đang chạy cũng là Huỷ, không kẹt', (WidgetTester tester) async {
      await pasteAndParse(tester);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('orderAi.parsing'), findsNothing);
      expect(find.text('orderAi.parse'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('Không huỷ thì vẫn nhận kết quả như thường', (WidgetTester tester) async {
      await pasteAndParse(tester);
      adapter.reply = <String, dynamic>{'cargos': <dynamic>[], 'warnings': <dynamic>[]};
      adapter.release.complete();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('orderAi.noCargo'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      // Gửi đúng lệnh đọc kiện
      expect(adapter.requests.single.path, '/orders/ai-parse-cargos');
      await tester.pump(const Duration(seconds: 4));
    });
  });
}
