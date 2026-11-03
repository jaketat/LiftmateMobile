// Khóa app: bật thì dừng ở màn đăng nhập, tắt thì vào thẳng; mật khẩu luôn là lối dự phòng
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liftmate_mobile/core/i18n.dart';
import 'package:liftmate_mobile/core/session.dart';
import 'package:liftmate_mobile/core/widgets/sf_symbol.dart';
import 'package:liftmate_mobile/features/auth/app_lock.dart';
import 'package:liftmate_mobile/features/auth/login_screen.dart';
import 'package:liftmate_mobile/features/auth/session_provider.dart';

class FakeBiometric extends BiometricAuth {
  BiometricResult result;
  BiometricKind available;
  int prompts = 0;

  FakeBiometric(this.result, {this.available = BiometricKind.faceId});

  @override
  Future<BiometricKind> kind() async => available;

  @override
  Future<BiometricResult> authenticate() async {
    prompts++;
    return result;
  }
}

Session sessionWith(List<String> permissions) => Session.fromJson(<String, dynamic>{
      'publicId': 'u1',
      'fullName': 'Hoàng Anh Quân',
      'role': 'CompanyAdmin',
      'permissions': permissions,
      'mustChangePassword': false,
      'company': <String, dynamic>{'companyName': 'Demo'},
    });

class FakeDriverSession extends SessionNotifier {
  @override
  Future<Session?> build() async => sessionWith(const <String>[]);
}

class FakeSession extends SessionNotifier {
  @override
  Future<Session?> build() async => Session.fromJson(<String, dynamic>{
        'publicId': 'u1',
        'username': 'anhquan',
        'fullName': 'Hoàng Anh Quân',
        'role': 'CompanyAdmin',
        'permissions': <String>['Orders.View'],
        'mustChangePassword': false,
        'company': <String, dynamic>{'companyName': 'Demo'},
      });
}

Future<ProviderContainer> container(FakeBiometric biometric) async {
  final ProviderContainer result = ProviderContainer(
    overrides: <dynamic>[
      sessionProvider.overrideWith(FakeSession.new),
      biometricAuthProvider.overrideWithValue(biometric),
    ].cast(),
  );
  await result.read(sessionProvider.future);
  await result.read(appLockProvider.future);
  return result;
}

void main() {
  setUp(() {
    I18n.useStrings(<String, String>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  testWidgets('Biểu tượng: Face ID dùng biểu tượng hệ thống của Apple trên iOS, Android dùng vân tay', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(const Directionality(textDirection: TextDirection.ltr, child: BiometricIcon(kind: BiometricKind.faceId, size: 24, color: Color(0xFF000000))));
    expect(tester.widget<SfSymbol>(find.byType(SfSymbol)).name, 'faceid');
    debugDefaultTargetPlatformOverride = null;

    await tester.pumpWidget(const Directionality(textDirection: TextDirection.ltr, child: BiometricIcon(kind: BiometricKind.fingerprint, size: 24, color: Color(0xFF000000))));
    expect(find.byType(SfSymbol), findsNothing);
    expect(find.byIcon(Icons.fingerprint), findsOneWidget);
  });

  group('Trạng thái khóa', () {
    test('Chưa bật thì không khóa, vào thẳng như cũ', () async {
      final ProviderContainer c = await container(FakeBiometric(BiometricResult.success));
      addTearDown(c.dispose);
      expect(c.read(appLockProvider).value!.isLockedFor('u1'), isFalse);
    });

    test('Bật rồi thì lần mở app sau bị khóa; đúng người mới bị, người khác cùng máy thì không', () async {
      final ProviderContainer first = await container(FakeBiometric(BiometricResult.success));
      await first.read(appLockProvider.notifier).enable('u1');
      // Vừa bật xong thì không tự khóa mình
      expect(first.read(appLockProvider).value!.isLockedFor('u1'), isFalse);
      first.dispose();

      final ProviderContainer reopened = await container(FakeBiometric(BiometricResult.success));
      addTearDown(reopened.dispose);
      final AppLockState state = reopened.read(appLockProvider).value!;
      expect(state.isLockedFor('u1'), isTrue);
      expect(state.isLockedFor('u2'), isFalse);
      expect(state.isLockedFor(null), isFalse);

      reopened.read(appLockProvider.notifier).unlock();
      expect(reopened.read(appLockProvider).value!.isLockedFor('u1'), isFalse);
    });

    test('Tắt rồi thì lần mở sau vào thẳng', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{'app_lock_user': 'u1'});
      final ProviderContainer c = await container(FakeBiometric(BiometricResult.success));
      await c.read(appLockProvider.notifier).disable();
      c.dispose();
      final ProviderContainer reopened = await container(FakeBiometric(BiometricResult.success));
      addTearDown(reopened.dispose);
      expect(reopened.read(appLockProvider).value!.isLockedFor('u1'), isFalse);
    });

    test('Rời app dưới 5 phút không khóa; từ 5 phút thì khóa và nhớ màn đang đứng', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{'app_lock_user': 'u1'});
      final ProviderContainer c = await container(FakeBiometric(BiometricResult.success));
      addTearDown(c.dispose);
      final AppLockNotifier lock = c.read(appLockProvider.notifier);
      lock.unlock();
      final DateTime start = DateTime(2026, 11, 2, 8);

      lock.noteLeftApp(start);
      lock.noteReturned(start.add(const Duration(minutes: 4, seconds: 59)), '/orders/o1');
      expect(c.read(appLockProvider).value!.isLockedFor('u1'), isFalse);
      expect(lock.takeReturnLocation(), isNull);

      // Nhiều sự kiện rời app liên tiếp vẫn tính từ lần đầu
      lock.noteLeftApp(start);
      lock.noteLeftApp(start.add(const Duration(minutes: 4)));
      lock.noteReturned(start.add(appLockGrace), '/orders/o1');
      expect(c.read(appLockProvider).value!.isLockedFor('u1'), isTrue);
      expect(lock.takeReturnLocation(), '/orders/o1');
      expect(lock.takeReturnLocation(), isNull);
    });

    test('Chưa bật khóa thì rời app bao lâu cũng không khóa', () async {
      final ProviderContainer c = await container(FakeBiometric(BiometricResult.success));
      addTearDown(c.dispose);
      final AppLockNotifier lock = c.read(appLockProvider.notifier);
      final DateTime start = DateTime(2026, 11, 2, 8);
      lock.noteLeftApp(start);
      lock.noteReturned(start.add(const Duration(hours: 5)), '/orders');
      expect(c.read(appLockProvider).value!.locked, isFalse);
    });
  });

  group('Tài xế không dùng khóa app', () {
    test('Đã bật từ trước (vd vừa đổi vai trò) vẫn không chặn; quản lý thì chặn', () {
      const AppLockState state = AppLockState(enabledFor: 'u1', locked: true);
      expect(state.blocks(sessionWith(const <String>[])), isFalse);
      expect(state.blocks(sessionWith(const <String>['Orders.View'])), isTrue);
      expect(state.blocks(null), isFalse);
      expect(canUseAppLock(sessionWith(const <String>[])), isFalse);
    });

    test('Rời app lâu rồi quay lại cũng không khóa tài xế', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{'app_lock_user': 'u1'});
      final ProviderContainer c = ProviderContainer(overrides: <dynamic>[sessionProvider.overrideWith(FakeDriverSession.new)].cast());
      addTearDown(c.dispose);
      await c.read(sessionProvider.future);
      await c.read(appLockProvider.future);
      final AppLockNotifier lock = c.read(appLockProvider.notifier);
      lock.unlock();
      final DateTime start = DateTime(2026, 11, 2, 8);
      lock.noteLeftApp(start);
      lock.noteReturned(start.add(const Duration(hours: 2)), '/driver/trips');
      expect(c.read(appLockProvider).value!.locked, isFalse);
      expect(lock.takeReturnLocation(), isNull);
    });

    testWidgets('Màn đăng nhập của tài xế là biểu mẫu thường, không hỏi Face ID', (WidgetTester tester) async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{'app_lock_user': 'u1'});
      tester.view.physicalSize = const Size(440 * 3, 956 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final FakeBiometric biometric = FakeBiometric(BiometricResult.success);
      final ProviderContainer c = ProviderContainer(
        overrides: <dynamic>[sessionProvider.overrideWith(FakeDriverSession.new), biometricAuthProvider.overrideWithValue(biometric)].cast(),
      );
      addTearDown(c.dispose);
      await tester.runAsync(() async {
        await c.read(sessionProvider.future);
        await c.read(appLockProvider.future);
      });
      await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const MaterialApp(home: LoginScreen())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(biometric.prompts, 0);
      expect(find.text('appLock.hello'), findsNothing);
    });
  });

  group('Màn đăng nhập', () {
    Future<void> pumpLogin(WidgetTester tester, ProviderContainer c) async {
      tester.view.physicalSize = const Size(440 * 3, 956 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const MaterialApp(home: LoginScreen())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('Đang khóa: tự hỏi Face ID một lần, điền sẵn tài khoản, đúng thì mở khóa', (WidgetTester tester) async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{'app_lock_user': 'u1'});
      final FakeBiometric biometric = FakeBiometric(BiometricResult.success);
      final ProviderContainer c = (await tester.runAsync(() => container(biometric)))!;
      addTearDown(c.dispose);
      await pumpLogin(tester, c);
      expect(biometric.prompts, 1);
      // Bố cục thẻ khóa: lời chào, tên, hai liên kết; không có ô tài khoản
      expect(find.text('appLock.hello'), findsOneWidget);
      expect(find.text('Hoàng Anh Quân'), findsOneWidget);
      expect(find.text('login.identifier'), findsNothing);
      expect(find.text('login.forgot'), findsOneWidget);
      expect(c.read(appLockProvider).value!.isLockedFor('u1'), isFalse);
    });

    testWidgets('Huỷ Face ID: vẫn dừng ở màn đăng nhập, không báo lỗi, bấm nút để thử lại', (WidgetTester tester) async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{'app_lock_user': 'u1'});
      final FakeBiometric biometric = FakeBiometric(BiometricResult.cancelled);
      final ProviderContainer c = (await tester.runAsync(() => container(biometric)))!;
      addTearDown(c.dispose);
      await pumpLogin(tester, c);
      expect(c.read(appLockProvider).value!.isLockedFor('u1'), isTrue);
      expect(find.text('appLock.failed'), findsNothing);
      // Vẫn còn ô mật khẩu làm lối dự phòng
      expect(find.text('login.password'), findsOneWidget);

      biometric.result = BiometricResult.success;
      expect(find.text('appLock.otherAccount'), findsOneWidget);
      await tester.tap(find.byType(BiometricIcon));
      await tester.pump();
      await tester.pump();
      expect(biometric.prompts, 2);
      expect(c.read(appLockProvider).value!.isLockedFor('u1'), isFalse);
    });

    testWidgets('Sinh trắc lỗi: báo dùng mật khẩu, vẫn khóa', (WidgetTester tester) async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{'app_lock_user': 'u1'});
      final ProviderContainer c = (await tester.runAsync(() => container(FakeBiometric(BiometricResult.failed))))!;
      addTearDown(c.dispose);
      await pumpLogin(tester, c);
      expect(find.text('appLock.failed'), findsOneWidget);
      expect(c.read(appLockProvider).value!.isLockedFor('u1'), isTrue);
    });

    testWidgets('Máy gỡ Face ID sau khi bật khóa: không hỏi, không ghi sai "vân tay", nhắc dùng mật khẩu', (WidgetTester tester) async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{'app_lock_user': 'u1'});
      final FakeBiometric biometric = FakeBiometric(BiometricResult.failed, available: BiometricKind.notEnrolled);
      final ProviderContainer c = (await tester.runAsync(() => container(biometric)))!;
      addTearDown(c.dispose);
      await pumpLogin(tester, c);
      expect(biometric.prompts, 0);
      expect(find.byType(BiometricIcon), findsNothing);
      expect(find.text('appLock.failed'), findsNothing);
      expect(find.text('appLock.unavailable'), findsOneWidget);
      expect(find.text('login.password'), findsOneWidget);
      expect(c.read(appLockProvider).value!.isLockedFor('u1'), isTrue);
    });

    testWidgets('Không khóa: màn đăng nhập như cũ, không hỏi Face ID, không có nút', (WidgetTester tester) async {
      final FakeBiometric biometric = FakeBiometric(BiometricResult.success);
      final ProviderContainer c = (await tester.runAsync(() => container(biometric)))!;
      addTearDown(c.dispose);
      await pumpLogin(tester, c);
      expect(biometric.prompts, 0);
      expect(find.byType(BiometricIcon), findsNothing);
      expect(find.text('appLock.hello'), findsNothing);
      expect(find.text('login.noAccount'), findsOneWidget);
    });
  });
}
