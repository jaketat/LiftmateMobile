// Nút trong trang mở gốc tab phải trượt vào; thanh tab thì đổi ngay
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liftmate_mobile/core/i18n.dart';
import 'package:liftmate_mobile/core/router.dart';
import 'package:liftmate_mobile/core/widgets/ios.dart';
import 'package:liftmate_mobile/core/widgets/page_transition.dart';

Future<GoRouter> pumpRouter(WidgetTester tester) async {
  final GoRouter router = GoRouter(
    initialLocation: '/dashboard',
    routes: withPageTransitions(<RouteBase>[
      GoRoute(path: '/dashboard', builder: (BuildContext context, GoRouterState state) => const Scaffold(body: Text('Trang chủ'))),
      GoRoute(path: '/orders', builder: (BuildContext context, GoRouterState state) => const Scaffold(body: Text('Đơn hàng'))),
    ]),
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  setUp(() => I18n.useStrings(<String, String>{}));

  testWidgets('Nút trong trang: trang cũ còn thấy trong lúc trượt, quay lại được và cũng trượt về', (WidgetTester tester) async {
    final GoRouter router = await pumpRouter(tester);
    pushTabRoot(tester.element(find.text('Trang chủ')), '/orders');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Trang chủ'), findsOneWidget);
    expect(find.text('Đơn hàng'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(router.canPop(), isTrue);

    router.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Đơn hàng'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Đơn hàng'), findsNothing);
    expect(find.text('Trang chủ'), findsOneWidget);
  });

  testWidgets('Thanh tab: đổi ngay, không có nút quay lại', (WidgetTester tester) async {
    final GoRouter router = await pumpRouter(tester);
    router.go('/orders');
    await tester.pump();
    await tester.pump();
    expect(find.text('Trang chủ'), findsNothing);
    expect(find.text('Đơn hàng'), findsOneWidget);
    expect(router.canPop(), isFalse);
  });

  testWidgets('Khoảng đáy cộng thêm phần thanh tab, giữ nguyên ba cạnh còn lại', (WidgetTester tester) async {
    late EdgeInsets result;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(padding: EdgeInsets.only(top: 50, bottom: 90)),
        child: Builder(
          builder: (BuildContext context) {
            result = withTabBarInset(context, const EdgeInsets.fromLTRB(16, 8, 12, 24));
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(result, const EdgeInsets.fromLTRB(16, 8, 12, 114));
  });

  testWidgets('Tiêu đề cùng hàng: tiêu đề và nút cùng đường giữa, có hay không có nút quay lại', (WidgetTester tester) async {
    for (final bool withBack in <bool>[false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          home: IosPage(
            key: ValueKey<bool>(withBack),
            title: 'Đơn hàng',
            inlineTitle: true,
            onBack: withBack ? () {} : null,
            trailing: const SizedBox(key: ValueKey<String>('nút'), width: 44, height: 44),
            slivers: const <Widget>[],
          ),
        ),
      );
      await tester.pump();
      final double title = tester.getCenter(find.text('Đơn hàng').first).dy;
      final double button = tester.getCenter(find.byKey(const ValueKey<String>('nút'))).dy;
      expect(title, closeTo(button, 1));
      expect(tester.takeException(), isNull);
    }
  });
}
