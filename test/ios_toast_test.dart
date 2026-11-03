// Thông báo kiểu iOS: hiện ở trên cùng, tự ẩn, thông báo mới thay thông báo cũ
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liftmate_mobile/core/widgets/ios.dart';

void main() {
  late BuildContext screen;

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (BuildContext context) {
        screen = context;
        return const Scaffold();
      }),
    ));
  }

  testWidgets('hiện ở nửa trên màn hình rồi tự ẩn', (WidgetTester tester) async {
    await pumpScreen(tester);
    showIosToast(screen, 'Đã lưu');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Đã lưu'), findsOneWidget);
    expect(tester.getCenter(find.text('Đã lưu')).dy, lessThan(100));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('Đã lưu'), findsNothing);
  });

  testWidgets('thông báo mới thay thông báo đang hiện', (WidgetTester tester) async {
    await pumpScreen(tester);
    showIosToast(screen, 'Thứ nhất');
    await tester.pump(const Duration(milliseconds: 500));
    showIosToast(screen, 'Thứ hai', isError: true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Thứ nhất'), findsNothing);
    expect(find.text('Thứ hai'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('chạm vào thì ẩn sớm', (WidgetTester tester) async {
    await pumpScreen(tester);
    showIosToast(screen, 'Đã lưu');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Đã lưu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('Đã lưu'), findsNothing);
    await tester.pumpAndSettle();
  });
}
