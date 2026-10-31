// Test chọn control: iOS dùng control native của cupertino_native, Android giữ bản Flutter.
import 'package:cupertino_native/cupertino_native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('Android giữ control Flutter', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await pumpControls(tester);
    expect(find.byType(CupertinoSwitch), findsOneWidget);
    expect(find.byType(CupertinoSlidingSegmentedControl<int>), findsOneWidget);
    expect(find.byType(CNSwitch), findsNothing);
    expect(find.byType(CNSegmentedControl), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS dùng control native, công tắc bị khóa khi không có onChanged', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pumpControls(tester);
    expect(find.byType(CNSwitch), findsOneWidget);
    expect(find.byType(CNSegmentedControl), findsOneWidget);
    expect(find.byType(CupertinoSwitch), findsNothing);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AdaptiveSwitch(value: true, activeColor: Colors.green, onChanged: null)),
    ));
    expect(tester.widget<CNSwitch>(find.byType(CNSwitch)).enabled, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });
}
