// Mọi vai trò dùng chung thanh tab kính; màn toàn màn hình thì giấu thanh tab
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liftmate_mobile/core/menu/main_shell.dart';
import 'package:liftmate_mobile/core/menu/menu_items.dart';
import 'package:liftmate_mobile/core/session.dart';
import 'package:liftmate_mobile/core/widgets/glass.dart';
import 'package:liftmate_mobile/features/auth/session_provider.dart';

class _FakeSession extends SessionNotifier {
  _FakeSession(this.session);

  final Session session;

  @override
  Future<Session?> build() async => session;
}

Session sessionWith(List<String> permissions) {
  return Session(fullName: 'A', companyName: 'B', roleName: 'C', permissions: permissions, mustChangePassword: false);
}

void main() {
  const List<String> allManagerPermissions = <String>['Reports.ViewOperations', 'Orders.View', 'Vehicles.View'];

  Future<void> pumpShell(WidgetTester tester, Session session, String location) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [sessionProvider.overrideWith(() => _FakeSession(session))],
      child: MaterialApp(home: MainShell(location: location, child: const SizedBox.expand())),
    ));
    await tester.pump();
  }

  testWidgets('Quản lý dùng thanh tab kính, đủ 5 tab vừa màn hẹp', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpShell(tester, sessionWith(allManagerPermissions), '/dashboard');
    expect(find.byType(NavigationBar), findsNothing);
    final GlassTabBar bar = tester.widget<GlassTabBar>(find.byType(GlassTabBar));
    expect(bar.items.length, 5);
    expect(bar.selectedIndex, 0);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Quản lý mở màn toàn màn hình thì thanh tab không bấm được', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await pumpShell(tester, sessionWith(allManagerPermissions), '/driver/trips/abc');
    await tester.pumpAndSettle();
    expect(find.byType(GlassTabBar).hitTestable(), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  test('Chỉ tài xế có Chuyến của tôi: ở thanh tab, không có trong menu Thêm của role khác', () {
    final Session manager = sessionWith(allManagerPermissions);
    expect(moreItemsFor(manager).map((AppMenuItem item) => item.path), isNot(contains('/driver/trips')));
    expect(tabsFor(manager).map((AppMenuItem item) => item.path), isNot(contains('/driver/trips')));

    final Session driver = sessionWith(const <String>[]);
    expect(tabsFor(driver).map((AppMenuItem item) => item.path), contains('/driver/trips'));
    expect(moreItemsFor(driver).map((AppMenuItem item) => item.path), isNot(contains('/driver/trips')));
  });
}
