// Khung chính sau khi đăng nhập: màn đang mở ở trên, thanh tab theo quyền ở dưới.
// Mọi màn của cả nhóm (trừ đăng nhập, đổi mật khẩu) nằm trong khung này.
import 'package:flutter/material.dart';
// Riverpod: ConsumerWidget, WidgetRef
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.go
import 'package:go_router/go_router.dart';

import '../../features/auth/session_provider.dart';
import '../session.dart';
import 'menu_items.dart';

class MainShell extends ConsumerWidget {
  // Đường dẫn đang mở, vd "/orders/123", để biết tab nào sáng
  final String location;
  // Màn đang mở
  final Widget child;

  const MainShell({super.key, required this.location, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Session? session = ref.watch(sessionProvider).value;
    // Bảo vệ ở router không cho vào đây khi chưa đăng nhập, dòng này chỉ để chắc chắn
    if (session == null) {
      return child;
    }

    final List<AppMenuItem> tabs = tabsFor(session);

    // Tab sáng: tab có đường dẫn là đầu của location ("/orders" sáng khi đang ở "/orders/123").
    // Không khớp tab nào (vd "/customers" mở từ màn Thêm) thì sáng tab cuối (Thêm / Tài khoản).
    int selectedIndex = tabs.length - 1;
    for (int index = 0; index < tabs.length; index++) {
      final String path = tabs[index].path;
      if (location == path || location.startsWith('$path/')) {
        selectedIndex = index;
        break;
      }
    }

    final List<NavigationDestination> destinations = <NavigationDestination>[];
    for (final AppMenuItem tab in tabs) {
      destinations.add(NavigationDestination(icon: Icon(tab.icon), label: tab.label));
    }

    return Scaffold(
      body: child,
      // NavigationBar (Flutter Material 3): thanh tab dưới
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        destinations: destinations,
        onDestinationSelected: (int index) {
          context.go(tabs[index].path);
        },
      ),
    );
  }
}

// Đường dẫn chưa có màn (người khác chưa làm xong) thì hiện màn này thay vì văng app
class NotReadyScreen extends StatelessWidget {
  final String location;

  const NotReadyScreen({super.key, required this.location});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Màn này đang làm.\n$location',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
