// Test vệt sáng của nút vuốt xác nhận: vệt dài, chạy hết chữ, lặp không có khoảng chết.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liftmate_mobile/core/i18n.dart';
import 'package:liftmate_mobile/features/driver/slide_to_confirm.dart';

void main() {
  test('mốc màu luôn tăng dần và trong khoảng 0–1 suốt một lượt', () {
    for (int step = 0; step <= 100; step++) {
      final List<double> stops = shineStops(step / 100);
      expect(stops.first, 0);
      expect(stops.last, 1);
      for (int index = 1; index < stops.length; index++) {
        expect(stops[index], greaterThanOrEqualTo(stops[index - 1]));
      }
    }
  });

  test('vệt vào từ ngoài mép trái, ra hết ngoài mép phải', () {
    // Mọi mốc của vệt đều dồn về mép: lúc này chưa thấy vệt hoặc vừa ra hết
    for (final double stop in shineStops(0).sublist(1, shineColors.length - 1)) {
      expect(stop, closeTo(0, 0.001));
    }
    for (final double stop in shineStops(1).sublist(1, shineColors.length - 1)) {
      expect(stop, closeTo(1, 0.001));
    }
  });

  test('giữa lượt: dải nằm giữa chữ và dài hơn nửa dòng', () {
    final List<double> middle = shineStops(0.5);
    expect(middle[shineColors.length ~/ 2], closeTo(0.5, 0.001));
    expect(middle[shineColors.length - 2] - middle[1], greaterThan(0.5));
  });

  test('số mốc khớp số màu; dải nhạt dần đều, không có mép cứng', () {
    expect(shineStops(0.5).length, shineColors.length);
    expect(shineColors.first, shineBaseColor);
    expect(shineColors.last, shineBaseColor);
    final int middle = shineColors.length ~/ 2;
    // Từ mép vào giữa: mỗi mốc sáng hơn mốc trước, và hai bên đối xứng
    for (int index = 1; index <= middle; index++) {
      expect(shineColors[index].computeLuminance(), greaterThanOrEqualTo(shineColors[index - 1].computeLuminance()));
      expect(shineColors[index], shineColors[shineColors.length - 1 - index]);
    }
  });

  Widget slider({bool enabled = true}) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: SlideToConfirm(label: 'Đã đến điểm bốc', enabled: enabled, onConfirmed: () async {}),
            ),
          ),
        ),
      );

  testWidgets('đang chờ vuốt thì vệt sáng lặp mãi, bị khóa thì không chạy', (WidgetTester tester) async {
    I18n.useStrings(<String, String>{});
    await tester.pumpWidget(slider());
    await tester.pump(shineDuration * 5);
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pumpWidget(slider(enabled: false));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('vệt sáng luôn hiện: chạm ngoài nút hay đang kéo núm đều không dừng', (WidgetTester tester) async {
    I18n.useStrings(<String, String>{});
    await tester.pumpWidget(slider());
    await tester.pump(const Duration(milliseconds: 100));

    // Chạm ở góc màn hình, ngoài nút vuốt
    final TestGesture outside = await tester.startGesture(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.hasRunningAnimations, isTrue);
    expect(find.byType(ShaderMask), findsOneWidget);
    await outside.up();

    // Đang kéo núm một đoạn ngắn
    final TestGesture knob = await tester.startGesture(tester.getCenter(find.byIcon(Icons.arrow_forward_rounded)));
    await knob.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.hasRunningAnimations, isTrue);
    expect(find.byType(ShaderMask), findsOneWidget);
    await knob.up();
    await tester.pump(const Duration(milliseconds: 400));
  });
}
