import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: GoRouter
import 'package:go_router/go_router.dart';

import 'core/i18n.dart';
import 'core/router.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Nạp chuỗi theo ngôn ngữ của máy (tiếng Việt / tiếng Anh) trước khi vẽ màn đầu tiên
  await I18n.load();
  runApp(ProviderScope(
      retry: noRetry,
      child: const LiftmateApp()
    ),
  );
}

Duration? noRetry(int retryCount, Object error) {
  return null;
}

// ConsumerWidget (Riverpod): có ref để lấy router từ hộp
class LiftmateApp extends ConsumerWidget {
  const LiftmateApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Lấy router từ hộp. Hộp tạo GoRouter 1 lần, các lần sau đưa lại đúng cái đó
    final GoRouter router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'LiftMate',
      routerConfig: router,
      theme: appTheme(),
      // Ngôn ngữ theo máy; lịch, bánh xe chọn ngày, nút hệ thống cũng đổi theo
      locale: I18n.locale,
      supportedLocales: const <Locale>[Locale('vi'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}
