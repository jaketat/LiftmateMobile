import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: GoRouter
import 'package:go_router/go_router.dart';

import 'core/router.dart';
import 'core/theme.dart';

void main() {
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
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}
