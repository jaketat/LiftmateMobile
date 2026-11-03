import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: GoRouter
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;

import 'core/i18n.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'core/widgets/glass.dart';
import 'features/auth/app_lock.dart';

// Lấy chế độ sáng / tối hiện tại của hệ thống cho bảng màu
void syncBrightness() {
  AppColors.isDark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  syncBrightness();
  // Nạp chuỗi theo ngôn ngữ của máy (tiếng Việt / tiếng Anh) trước khi vẽ màn đầu tiên
  await I18n.load();
  final Widget app = ProviderScope(
    retry: noRetry,
    child: const LiftmateApp(),
  );
  if (useNativeControls) {
    await lg.LiquidGlassWidgets.initialize(enablePerformanceMonitor: false);
    runApp(lg.LiquidGlassWidgets.wrap(child: app));
    return;
  }
  runApp(app);
}

Duration? noRetry(int retryCount, Object error) {
  return null;
}

// ConsumerWidget (Riverpod): có ref để lấy router từ hộp
class LiftmateApp extends ConsumerStatefulWidget {
  const LiftmateApp({super.key});

  @override
  ConsumerState<LiftmateApp> createState() => _LiftmateAppState();
}

class _LiftmateAppState extends ConsumerState<LiftmateApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Rời app quá lâu rồi quay lại thì khóa, nếu người dùng bật khóa app
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    final AppLockNotifier lock = ref.read(appLockProvider.notifier);
    if (lifecycle == AppLifecycleState.hidden || lifecycle == AppLifecycleState.paused) {
      lock.noteLeftApp(DateTime.now());
    } else if (lifecycle == AppLifecycleState.resumed) {
      lock.noteReturned(DateTime.now(), ref.read(routerProvider).routerDelegate.currentConfiguration.uri.toString());
    }
  }

  // Đổi sáng / tối trong Cài đặt khi app đang mở: màu đọc lúc build nên phải dựng lại toàn bộ cây,
  // giữ nguyên route và trạng thái các màn
  @override
  void didChangePlatformBrightness() {
    syncBrightness();
    void rebuild(Element element) {
      element.markNeedsBuild();
      element.visitChildren(rebuild);
    }
    setState(() {});
    (context as Element).visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) {
    // Lấy router từ hộp. Hộp tạo GoRouter 1 lần, các lần sau đưa lại đúng cái đó
    final GoRouter router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'LiftMate',
      routerConfig: router,
      theme: appTheme(),
      // Nền dưới mọi trang: màn đăng nhập và màn chính lộ dần theo gợn sóng, màn cũ đã bị gỡ nên phần chưa lộ không được để đen
      builder: (BuildContext context, Widget? child) => ColoredBox(color: AppColors.surface, child: child),
      // Ngôn ngữ theo máy; lịch, bánh xe chọn ngày, nút hệ thống cũng đổi theo
      locale: I18n.locale,
      supportedLocales: const <Locale>[Locale('vi'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}
