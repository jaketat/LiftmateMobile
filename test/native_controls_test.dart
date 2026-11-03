// Test chọn control: iOS dùng công tắc native và bộ lọc của liquid_glass_widgets, Android giữ bản Flutter.
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;
import 'package:liftmate_mobile/core/widgets/ios.dart';
import 'package:liftmate_mobile/features/driver/driver_widgets.dart';

void main() {
  Future<void> pumpControls(WidgetTester tester) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: <Widget>[
            GlassSegmented(labels: const <String>['A', 'B'], selected: 0, onChanged: (_) {}),
            AdaptiveSwitch(value: true, activeColor: Colors.green, onChanged: (_) {}),
          ],
        ),
      ),
    ));
  }

  final Finder nativeSwitch = find.byWidgetPredicate((Widget widget) => widget is UiKitView && widget.viewType == 'liftmate/switch');

  testWidgets('Android giữ control Flutter', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await pumpControls(tester);
    expect(find.byType(CupertinoSwitch), findsOneWidget);
    expect(find.byType(CupertinoSlidingSegmentedControl<int>), findsOneWidget);
    expect(nativeSwitch, findsNothing);
    expect(find.byType(lg.GlassSegmentedControl), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS dùng control native, công tắc bị khóa khi không có onChanged', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    // Test không có phần native thật: trả lời giả lệnh tạo view
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, (MethodCall call) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, null));
    await pumpControls(tester);
    expect(nativeSwitch, findsOneWidget);
    expect(find.byType(lg.GlassSegmentedControl), findsOneWidget);
    // Bản Flutter vẫn nằm trong cây để đổi qua lại không nháy, nhưng không nhận chạm khi đang dùng native
    expect(find.byType(CupertinoSwitch).hitTestable(), findsNothing);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AdaptiveSwitch(value: true, activeColor: Colors.green, onChanged: null)),
    ));
    final UiKitView view = tester.widget<UiKitView>(nativeSwitch);
    expect((view.creationParams as Map<String, Object?>)['enabled'], isFalse);
    debugDefaultTargetPlatformOverride = null;
  });
}
