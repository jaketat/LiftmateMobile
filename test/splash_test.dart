// Test màn khởi động: giữ đến khi logo lắp xong, logo bay sang đăng nhập, lỗi thì có Thử lại.
import 'package:ai_glow/ai_glow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:liftmate_mobile/core/api/call.dart';
import 'package:liftmate_mobile/core/i18n.dart';
import 'package:liftmate_mobile/core/menu/main_shell.dart';
import 'package:liftmate_mobile/core/router.dart';
import 'package:liftmate_mobile/core/session.dart';
import 'package:liftmate_mobile/features/auth/login_screen.dart';
import 'package:liftmate_mobile/features/auth/ripple_transition.dart';
import 'package:liftmate_mobile/features/auth/session_provider.dart';
import 'package:liftmate_mobile/features/auth/splash_screen.dart';

// Chưa đăng nhập: có kết quả ngay
class LoggedOut extends SessionNotifier {
  @override
  Future<Session?> build() async {
    return null;
  }
}

// Lần đầu mất mạng, lần sau chờ mãi để thấy trạng thái đang tải
class FailsOnce extends SessionNotifier {
  static int calls = 0;

  @override
  Future<Session?> build() {
    calls = calls + 1;
    if (calls == 1) {
      return Future<Session?>.error(ApiException(null, null, 'Mất mạng'));
    }
    return Future<Session?>.delayed(const Duration(days: 1));
  }
}

// Đã đăng nhập, không có quyền gì: tab đầu tiên là "/more"
class LoggedIn extends SessionNotifier {
  @override
  Future<Session?> build() async {
    return Session(fullName: 'An', companyName: 'LM', roleName: 'NV', permissions: const <String>[], mustChangePassword: false);
  }
}

Duration? noRetry(int retryCount, Object error) {
  return null;
}

Future<void> pumpApp(WidgetTester tester, SessionNotifier Function() session) async {
  await tester.pumpWidget(ProviderScope(
    retry: noRetry,
    overrides: <dynamic>[sessionProvider.overrideWith(session)].cast(),
    child: Consumer(
      builder: (BuildContext context, WidgetRef ref, Widget? child) {
        final GoRouter router = ref.watch(routerProvider);
        return MaterialApp.router(routerConfig: router);
      },
    ),
  ));
}

void main() {
  setUp(() {
    I18n.useStrings(<String, String>{});
    FailsOnce.calls = 0;
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('chưa đăng nhập: giữ màn khởi động đủ giờ rồi mới sang đăng nhập', (WidgetTester tester) async {
    await pumpApp(tester, LoggedOut.new);
    await tester.pump(const Duration(milliseconds: 1250));
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    // Lúc này chữ đã hiện đủ 8 ký tự
    expect(find.text('L'), findsOneWidget);
    expect(find.text('e'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    // Chấm màu nền chạy mãi nên không dùng pumpAndSettle
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
  });

  testWidgets('logo bay từ màn khởi động về chỗ của nó trên màn đăng nhập', (WidgetTester tester) async {
    await pumpApp(tester, LoggedOut.new);
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Giữa đường: logo đang bay có chiều cao nằm giữa 206 (khởi động) và 116 (đăng nhập)
    final double flying = tester.getSize(find.byKey(const ValueKey<String>('mark-flight'))).height;
    expect(flying, lessThan(206));
    expect(flying, greaterThan(116));
    // Gợn sáng chạy cùng lúc logo bay, xong thì biến mất
    expect(find.byType(InnerAiGlowing), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey<String>('mark-flight')), findsNothing);
    expect(find.byType(InnerAiGlowing), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('đã đăng nhập: gợn sáng chạy lúc vào màn chính, xong thì biến mất', (WidgetTester tester) async {
    await pumpApp(tester, LoggedIn.new);
    await tester.pump(const Duration(milliseconds: 1400));
    expect(find.byType(SplashScreen), findsOneWidget);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Gợn đang chạy: màn chính đã dựng sẵn bên dưới, bản đồ còn đợi, không có viền blur nặng
    expect(find.byType(MainShell), findsOneWidget);
    expect(entranceRunning.value, isTrue);
    expect(find.byType(InnerAiGlowing), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    expect(entranceRunning.value, isFalse);
    expect(find.byType(SplashScreen), findsNothing);
    expect(find.byType(MainShell), findsOneWidget);
  });

  testWidgets('mất mạng: hiện lỗi, bấm Thử lại thì quay về đang tải', (WidgetTester tester) async {
    await pumpApp(tester, FailsOnce.new);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2800));
    expect(find.text('Mất mạng'), findsOneWidget);

    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pump();
    expect(FailsOnce.calls, 2);
    expect(find.text('Mất mạng'), findsNothing);
    expect(find.byType(SplashScreen), findsOneWidget);

    // Dọn đồng hồ của lần tải đang chờ
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(days: 2));
  });
}
