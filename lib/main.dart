import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

class LiftmateApp extends StatelessWidget {
  const LiftmateApp({super.key});

  @override
  Widget build(BuildContext context) {
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
