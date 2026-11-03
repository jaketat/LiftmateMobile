// Hiệu ứng AI: phải tự tắt hẳn khi hết việc, không chặn chạm, không chạy khi người dùng tắt chuyển động
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liftmate_mobile/core/widgets/liftmate_intelligence.dart';

Widget host(Widget child, {bool disableAnimations = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: const Size(440, 956), disableAnimations: disableAnimations),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  test('Vòng màu khép kín và không có xanh lá', () {
    expect(aiGlowColors.first, aiGlowColors.last);
    for (final Color color in aiGlowColors) {
      final double hue = HSVColor.fromColor(color).hue;
      expect(hue > 80 && hue < 170, isFalse);
    }
  });

  testWidgets('Ô soạn: chưa có chữ thì ẩn mũi tên; có chữ mới gửi được; chưa đủ điều kiện thì mũi tên không nhận chạm', (WidgetTester tester) async {
    final TextEditingController text = TextEditingController();
    addTearDown(text.dispose);
    int sends = 0;
    Widget field(VoidCallback? onSend) => host(Center(child: AiPromptField(controller: text, placeholder: 'Dán', glow: false, onChanged: (String _) {}, onSend: onSend)));

    await tester.pumpWidget(field(() => sends++));
    await tester.pump();
    Visibility arrow() => tester.widget<Visibility>(find.ancestor(of: find.byIcon(CupertinoIcons.arrow_up_circle), matching: find.byType(Visibility)).first);
    expect(arrow().visible, isFalse);

    text.text = 'Hai máy tiện';
    await tester.pumpWidget(field(() => sends++));
    await tester.pump();
    await tester.tap(find.byIcon(CupertinoIcons.arrow_up_circle));
    expect(sends, 1);

    await tester.pumpWidget(field(null));
    await tester.pump();
    await tester.tap(find.byIcon(CupertinoIcons.arrow_up_circle), warnIfMissed: false);
    expect(sends, 1);
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('Logo vẽ được ở các cỡ dùng trong app, không xin khung hình', (WidgetTester tester) async {
    await tester.pumpWidget(host(const Column(children: <Widget>[AiOrb(size: 28), AiOrb(size: 30), AiOrb(size: 40)])));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(AiOrb).last), const Size(40, 40));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('Ô soạn: gõ dài thì giãn cao, không tràn', (WidgetTester tester) async {
    final TextEditingController text = TextEditingController();
    addTearDown(text.dispose);
    Widget field() => host(Center(child: AiPromptField(controller: text, placeholder: 'Dán', glow: false, onChanged: (String _) {})));
    await tester.pumpWidget(field());
    await tester.pump();
    final double single = tester.getSize(find.byType(AiPromptField)).height;

    text.text = List<String>.filled(40, 'máy tiện CNC').join(' ');
    await tester.pumpWidget(field());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getSize(find.byType(AiPromptField)).height, greaterThan(single));
  });

  testWidgets('Viền sáng màn hình: bật thì vẽ, hết việc thì mờ dần rồi gỡ, không để đồng hồ chạy', (WidgetTester tester) async {
    await tester.pumpWidget(host(const AiScreenGlow(active: true, child: SizedBox.expand())));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.descendant(of: find.byType(AiScreenGlow), matching: find.byType(RepaintBoundary)), findsWidgets);
    expect(tester.binding.hasScheduledFrame, isTrue);

    await tester.pumpWidget(host(const AiScreenGlow(active: false, child: SizedBox.expand())));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.descendant(of: find.byType(AiScreenGlow), matching: find.byType(TweenAnimationBuilder<double>)), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('Viền sáng không chặn chạm vào nội dung bên dưới', (WidgetTester tester) async {
    int taps = 0;
    await tester.pumpWidget(
      host(AiScreenGlow(active: true, child: Center(child: TextButton(onPressed: () => taps++, child: const Text('Bấm'))))),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Bấm'));
    expect(taps, 1);
  });

  testWidgets('Tắt chuyển động trong máy thì các hiệu ứng đứng yên', (WidgetTester tester) async {
    await tester.pumpWidget(
      host(
        const AiGlow(radius: 20, child: Column(children: <Widget>[AiGeneratingLines(), AiShimmerText('Đang đọc', style: TextStyle())])),
        disableAnimations: true,
      ),
    );
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('Hiện chữ: chạy một lần rồi trả nguyên nội dung; hủy giữa chừng không lỗi', (WidgetTester tester) async {
    await tester.pumpWidget(host(const AiReveal(delay: Duration(milliseconds: 100), child: Text('Kiện'))));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(Opacity), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Kiện'), findsOneWidget);
    expect(find.descendant(of: find.byType(AiReveal), matching: find.byType(Opacity)), findsNothing);

    await tester.pumpWidget(host(const AiReveal(key: ValueKey<int>(2), delay: Duration(seconds: 5), child: Text('Kiện'))));
    await tester.pumpWidget(host(const SizedBox.shrink()));
  });

  testWidgets('Nút AI: bấm được thì có viền và chữ màu; hình đứng yên, không tốn khung hình', (WidgetTester tester) async {
    int taps = 0;
    await tester.pumpWidget(host(Center(child: AiButton(label: 'Đọc', onPressed: () => taps++))));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.descendant(of: find.byType(AiButton), matching: find.byType(AiGradient)), findsOneWidget);
    await tester.tap(find.text('Đọc'));
    expect(taps, 1);
  });

  testWidgets('Nút AI chưa bấm được thì xám, không nhận chạm', (WidgetTester tester) async {
    await tester.pumpWidget(host(const Center(child: AiButton(label: 'Đọc', onPressed: null))));
    await tester.pump();
    expect(find.descendant(of: find.byType(AiButton), matching: find.byType(AiGradient)), findsNothing);
    await tester.tap(find.text('Đọc'), warnIfMissed: false);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('Câu có tên LiftMate Intelligence: chỉ riêng tên có dải màu', (WidgetTester tester) async {
    await tester.pumpWidget(host(const AiBrandText('Create with LiftMate Intelligence')));
    await tester.pump();
    expect(find.descendant(of: find.byType(AiGradient), matching: find.text('LiftMate Intelligence')), findsOneWidget);
    expect(find.textContaining('Create with', findRichText: true), findsOneWidget);

    await tester.pumpWidget(host(const AiBrandText('Không có tên')));
    await tester.pump();
    expect(find.byType(AiGradient), findsNothing);
    expect(find.text('Không có tên'), findsOneWidget);
  });

  test('Bảng màu chữ khớp ảnh mẫu: bắt đầu xanh, kết thúc cam', () {
    expect(aiTextColors.first, const Color(0xFF109DF7));
    expect(aiTextColors.last, const Color(0xFFF99911));
  });

  testWidgets('Bấm giữ thì phóng to và sáng lên, thả ra về cỡ cũ rồi dừng hẳn', (WidgetTester tester) async {
    int taps = 0;
    await tester.pumpWidget(host(Center(child: AiPressEffect(pressedScale: 1.18, radius: 22, child: GestureDetector(onTap: () => taps++, child: const SizedBox(width: 44, height: 44, child: ColoredBox(color: Colors.blue)))))));
    double scale() => tester.widget<ScaleTransition>(find.descendant(of: find.byType(AiPressEffect), matching: find.byType(ScaleTransition))).scale.value;
    double light() => tester.widgetList<FadeTransition>(find.descendant(of: find.byType(AiPressEffect), matching: find.byType(FadeTransition))).first.opacity.value;
    expect(scale(), 1);

    final TestGesture finger = await tester.startGesture(tester.getCenter(find.byType(ColoredBox).last));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(scale(), closeTo(1.18, 0.02));
    expect(light(), 1);

    await finger.up();
    await tester.pumpAndSettle();
    expect(scale(), closeTo(1, 0.001));
    expect(light(), 0);
    expect(taps, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('Nút đang khóa thì bấm không có hiệu ứng', (WidgetTester tester) async {
    await tester.pumpWidget(host(const Center(child: AiPressEffect(pressedScale: 1.18, radius: 22, enabled: false, child: SizedBox(width: 44, height: 44, child: ColoredBox(color: Colors.blue))))));
    final TestGesture finger = await tester.startGesture(tester.getCenter(find.byType(ColoredBox).last));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<ScaleTransition>(find.descendant(of: find.byType(AiPressEffect), matching: find.byType(ScaleTransition))).scale.value, 1);
    await finger.up();
  });

  testWidgets('Không animate thì hiện ngay', (WidgetTester tester) async {
    await tester.pumpWidget(host(const AiReveal(animate: false, child: Text('Chữ dán tay'))));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.text('Chữ dán tay'), findsOneWidget);
  });
}
