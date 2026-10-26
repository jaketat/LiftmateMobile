// Khung chính sau khi đăng nhập: màn đang mở ở trên, thanh tab theo quyền ở dưới.
// Mọi màn của cả nhóm (trừ đăng nhập, đổi mật khẩu) nằm trong khung này.
import 'package:flutter/material.dart';
// Riverpod: ConsumerWidget, WidgetRef
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.go
import 'package:go_router/go_router.dart';

import '../../features/auth/session_provider.dart';
import '../session.dart';
import '../widgets/glass.dart';
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

    // Việc trong một chuyến (chi tiết chuyến, ảnh, báo hỏng, đồng ý vị trí): toàn màn, không thanh tab,
    // như app gọi xe. Thoát bằng nút quay lại.
    if (isFullScreenDriverTask(location)) {
      return child;
    }

    final List<AppMenuItem> tabs = tabsFor(session);

    // Tab sáng: tab có đường dẫn là đầu của location ("/orders" sáng khi đang ở "/orders/123").
    // Không khớp tab nào (vd "/customers" mở từ màn Thêm) thì sáng tab cuối (Thêm / Tài khoản).
    int selectedIndex = tabs.length - 1;
    // Màn báo hỏng mở từ một chuyến vẫn thuộc tab "Báo hỏng"
    final String tabLocation = isBreakdownForm(location) ? '/driver/breakdowns/new' : location;
    for (int index = 0; index < tabs.length; index++) {
      final String path = tabs[index].path;
      if (tabLocation == path || tabLocation.startsWith('$path/')) {
        selectedIndex = index;
        break;
      }
    }

    if (usesDriverMenu(session)) {
      return _driverShell(context, tabs, selectedIndex);
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

// Tài xế: thanh tab kính nổi (iOS 26 Liquid Glass). Riêng trang chủ bản đồ thì nội dung tràn
// xuống dưới thanh tab (extendBody), các tab khác giữ nội dung ở trên thanh để không bị che.
extension on MainShell {
  Widget _driverShell(BuildContext context, List<AppMenuItem> tabs, int selectedIndex) {
    final List<GlassTabItem> items = <GlassTabItem>[];
    for (final AppMenuItem tab in tabs) {
      items.add(GlassTabItem(icon: tab.icon, selectedIcon: tab.selectedIcon ?? tab.icon, label: tab.label));
    }
    // Bản đồ và các màn báo hỏng (nền kính) cho nội dung chạy xuống dưới thanh tab kính
    final bool overMap = location == '/driver/trips' ||
        location == '/driver/breakdowns' ||
        isBreakdownForm(location) ||
        location == '/more' ||
        location.startsWith('/account/');
    return Scaffold(
      extendBody: overMap,
      body: child,
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: GlassTabBar(
            items: items,
            selectedIndex: selectedIndex,
            onSelected: (int index) {
              context.go(tabs[index].path);
            },
          ),
        ),
      ),
    );
  }
}

// Màn toàn màn hình của tài xế: mọi đường dẫn bên trong một chuyến, và màn đồng ý chia sẻ vị trí
// Riêng màn báo hỏng (/driver/trips/:id/breakdown, /driver/breakdowns/new) vẫn giữ thanh tab, sáng tab "Báo hỏng".
bool isFullScreenDriverTask(String location) {
  if (isBreakdownForm(location)) {
    return false;
  }
  return location.startsWith('/driver/trips/') || location == '/driver/location-consent';
}

bool isBreakdownForm(String location) {
  return location == '/driver/breakdowns/new' ||
      (location.startsWith('/driver/trips/') && location.endsWith('/breakdown'));
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
