// Nút Chốt lịch ở màn chuyến chạy đi theo allowedActions của đơn, không phải lúc nào cũng hiện
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liftmate_mobile/core/i18n.dart';
import 'package:liftmate_mobile/core/session.dart';
import 'package:liftmate_mobile/features/auth/session_provider.dart';
import 'package:liftmate_mobile/features/orders/orders_api.dart';
import 'package:liftmate_mobile/features/planning/run_trips_api.dart';
import 'package:liftmate_mobile/features/planning/run_trips_providers.dart';
import 'package:liftmate_mobile/features/planning/run_trips_screen.dart';

class Dispatcher extends SessionNotifier {
  @override
  Future<Session?> build() async {
    return Session(fullName: 'An', companyName: 'LM', roleName: 'DP', permissions: const <String>['Orders.Dispatch'], mustChangePassword: false);
  }
}

Future<void> pump(WidgetTester tester, List<String> allowedActions) async {
  await tester.pumpWidget(ProviderScope(
    overrides: <dynamic>[
      sessionProvider.overrideWith(Dispatcher.new),
      runTripsProvider('o1').overrideWith((Ref ref) async => <RunTrip>[]),
      orderDetailProvider('o1').overrideWith((Ref ref) async => OrderDetail.fromJson(<String, dynamic>{
            'publicId': 'o1',
            'orderCode': 'DH-1',
            'status': 'CustomerConfirmed',
            'allowedActions': allowedActions,
            'createdAt': '2026-10-01T03:00:00Z',
          })),
    ].cast(),
    child: const MaterialApp(home: RunTripsScreen(orderId: 'o1')),
  ));
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() => I18n.useStrings(<String, String>{}));

  testWidgets('đơn còn chốt được thì có nút Chốt lịch', (WidgetTester tester) async {
    await pump(tester, <String>['schedule', 'cancel']);
    expect(find.text('orderAction.schedule'), findsOneWidget);
    expect(find.text('planning.run.createFromPlan'), findsOneWidget);
  });

  testWidgets('đơn đã chốt lịch thì ẩn nút, vẫn tạo được chuyến', (WidgetTester tester) async {
    await pump(tester, <String>['start', 'cancel']);
    expect(find.text('orderAction.schedule'), findsNothing);
    expect(find.text('planning.run.scheduleHint'), findsNothing);
    expect(find.text('planning.run.createFromPlan'), findsOneWidget);
  });
}
