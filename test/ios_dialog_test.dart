// Test hộp thoại kiểu iOS 26: trả đúng kết quả, xếp nút đúng, nút hủy nổi bật khi hành động nguy hiểm.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liftmate_mobile/core/i18n.dart';
import 'package:liftmate_mobile/core/theme.dart';
import 'package:liftmate_mobile/core/widgets/ios.dart';

Future<bool?> Function() _opener(WidgetTester tester, {required String action, bool destructive = true, String? message}) {
  bool? result;
  return () async {
    final BuildContext context = tester.element(find.byType(Scaffold));
    showIosConfirm(context, title: 'Tiêu đề', message: message, action: action, destructive: destructive, cancel: 'Hủy')
        .then((bool value) => result = value);
    await tester.pumpAndSettle();
    return result;
  };
}

Color _buttonColor(WidgetTester tester, String label) {
  final Finder button = find.ancestor(of: find.text(label), matching: find.byType(CupertinoButton));
  return tester.widget<CupertinoButton>(button.first).color!;
}

void main() {
  setUp(() => I18n.useStrings(<String, String>{}));

  Future<void> host(WidgetTester tester) => tester.pumpWidget(const MaterialApp(home: Scaffold()));

  testWidgets('bấm nút hành động trả true, nút hủy và chạm ngoài trả false', (WidgetTester tester) async {
    await host(tester);
    final BuildContext context = tester.element(find.byType(Scaffold));
    Future<void> check(Future<void> Function() close, bool expected) async {
      bool? result;
      showIosConfirm(context, title: 'T', action: 'Xóa', cancel: 'Hủy').then((bool value) => result = value);
      await tester.pumpAndSettle();
      await close();
      await tester.pumpAndSettle();
      expect(result, expected);
    }

    await check(() => tester.tap(find.text('Xóa')), true);
    await check(() => tester.tap(find.text('Hủy')), false);
    await check(() => tester.tapAt(const Offset(5, 5)), false);
  });

  testWidgets('lúc đang mở, lớp kính không nằm trong lớp độ trong suốt nên làm mờ được ngay từ đầu', (WidgetTester tester) async {
    await host(tester);
    final BuildContext context = tester.element(find.byType(Scaffold));
    showIosConfirm(context, title: 'T', action: 'Xóa', cancel: 'Hủy');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    final Finder glass = find.descendant(of: find.byType(IosDialog), matching: find.byType(BackdropFilter));
    expect(glass, findsOneWidget);
    expect(find.ancestor(of: glass, matching: find.byType(FadeTransition)), findsNothing);
    expect(find.ancestor(of: glass, matching: find.byType(Opacity)), findsNothing);

    // Giữa lúc mở: độ mờ đã tăng dần, chưa tới mức cuối
    final BackdropFilter midway = tester.widget<BackdropFilter>(glass);
    await tester.pumpAndSettle();
    final BackdropFilter settled = tester.widget<BackdropFilter>(glass);
    expect(midway.filter, isNot(settled.filter));
    expect(tester.widget<Opacity>(find.descendant(of: glass, matching: find.byType(Opacity)).first).opacity, 1);
  });

  testWidgets('chạm vào hộp thì phóng nhẹ, buông ra về đúng cỡ, nút bên trong vẫn bấm được', (WidgetTester tester) async {
    await host(tester);
    final BuildContext context = tester.element(find.byType(Scaffold));
    bool? result;
    showIosConfirm(context, title: 'Tiêu đề', action: 'Xóa', cancel: 'Hủy').then((bool value) => result = value);
    await tester.pumpAndSettle();

    double scale() => tester.widget<ScaleTransition>(find.descendant(of: find.byType(IosPressBounce), matching: find.byType(ScaleTransition))).scale.value;
    expect(scale(), 1);

    final TestGesture press = await tester.startGesture(tester.getCenter(find.text('Tiêu đề')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(scale(), greaterThan(1));
    await press.up();
    await tester.pumpAndSettle();
    expect(scale(), closeTo(1, 0.002));
    expect(result, isNull);

    await tester.tap(find.text('Xóa'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('hành động nguy hiểm: nút hủy nổi bật, nút hành động xám chữ đỏ', (WidgetTester tester) async {
    await host(tester);
    await _opener(tester, action: 'Xóa')();
    expect(_buttonColor(tester, 'Hủy'), AppColors.navy);
    expect(_buttonColor(tester, 'Xóa'), IosDialog.secondaryFill);
    expect(tester.widget<Text>(find.text('Xóa')).style!.color, IosColors.red);
  });

  testWidgets('hành động thường: nút hành động nổi bật, nút hủy xám', (WidgetTester tester) async {
    await host(tester);
    await _opener(tester, action: 'Vẫn mở', destructive: false)();
    expect(_buttonColor(tester, 'Vẫn mở'), AppColors.navy);
    expect(_buttonColor(tester, 'Hủy'), IosDialog.secondaryFill);
  });

  testWidgets('nhãn ngắn xếp ngang: hủy bên trái, hành động bên phải; chữ căn trái', (WidgetTester tester) async {
    await host(tester);
    await _opener(tester, action: 'Xóa', message: 'Không hoàn tác được')();
    final Offset cancel = tester.getCenter(find.text('Hủy'));
    final Offset action = tester.getCenter(find.text('Xóa'));
    expect(cancel.dy, action.dy);
    expect(cancel.dx, lessThan(action.dx));
    expect(tester.getTopLeft(find.text('Tiêu đề')).dx, tester.getTopLeft(find.text('Không hoàn tác được')).dx);
    expect(tester.widget<Text>(find.text('Tiêu đề')).textAlign, TextAlign.start);
  });

  testWidgets('nhãn dài xếp dọc, nút hành động ở trên, không tràn', (WidgetTester tester) async {
    await host(tester);
    await _opener(tester, action: 'Rút lại đồng ý chia sẻ vị trí của tôi')();
    final Offset cancel = tester.getCenter(find.text('Hủy'));
    final Offset action = tester.getCenter(find.text('Rút lại đồng ý chia sẻ vị trí của tôi'));
    expect(action.dy, lessThan(cancel.dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('nội dung rất dài không tràn trên màn nhỏ, nút vẫn bấm được', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await host(tester);
    await _opener(tester, action: 'Xóa', message: List<String>.filled(200, 'chữ').join(' '))();
    expect(tester.takeException(), isNull);
    expect(find.text('Xóa').hitTestable(), findsOneWidget);
  });

  testWidgets('nút bị khóa không bấm được', (WidgetTester tester) async {
    await host(tester);
    bool pressed = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: IosDialog(
          title: 'T',
          actions: <IosDialogAction>[
            IosDialogAction(label: 'Hủy', style: IosDialogActionStyle.primary, onPressed: () => pressed = true),
            const IosDialogAction(label: 'Xóa', style: IosDialogActionStyle.destructive, onPressed: null),
          ],
        ),
      ),
    ));
    await tester.tap(find.text('Xóa'));
    await tester.pump();
    expect(pressed, isFalse);
  });

  testWidgets('menu có nút nguồn bật ra ngay dưới nút, chọn được, chạm ra ngoài là hủy', (WidgetTester tester) async {
    String? picked = 'chưa';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () async {
                  picked = await showIosActionSheet<String>(
                    context,
                    anchor: context,
                    options: const <IosSheetOption<String>>[IosSheetOption<String>('huy', 'Hủy đơn', destructive: true)],
                  );
                },
                child: const Text('nút'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('nút'));
    await tester.pumpAndSettle();
    final Rect button = tester.getRect(find.text('nút'));
    final Rect item = tester.getRect(find.text('Hủy đơn'));
    expect(item.top, greaterThan(button.top));
    expect(item.top, lessThan(button.bottom + 60));
    expect(item.right, greaterThan(tester.view.physicalSize.width / tester.view.devicePixelRatio - 120));

    await tester.tapAt(const Offset(40, 500));
    await tester.pumpAndSettle();
    expect(picked, isNull);

    await tester.tap(find.text('nút'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hủy đơn'));
    await tester.pumpAndSettle();
    expect(picked, 'huy');
  });
}
