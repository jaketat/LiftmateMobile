// Danh sách DUY NHẤT các tab và mục menu: chữ, biểu tượng, đường dẫn, quyền cần có (doc mục 2.8).
// Hiện theo quyền, không theo tên vai trò (công ty tự đặt được vai trò riêng).
// Thêm hay đổi mục menu thì chỉ sửa file này.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../session.dart';
import '../i18n.dart';

class AppMenuItem {
  final String label;
  final IconData icon;
  // Biểu tượng tô đặc khi tab đang chọn (thanh tab kính của tài xế)
  final IconData? selectedIcon;
  final String path;
  // Có ít nhất 1 quyền trong danh sách thì hiện. Danh sách rỗng thì ai cũng thấy.
  final List<String> anyOf;

  const AppMenuItem({
    required this.label,
    required this.icon,
    this.selectedIcon,
    required this.path,
    this.anyOf = const <String>[],
  });

  bool isVisibleFor(Session session) {
    if (anyOf.isEmpty) {
      return true;
    }
    for (final String permission in anyOf) {
      if (session.can(permission)) {
        return true;
      }
    }
    return false;
  }
}

// Tab của quản lý (giám đốc, điều phối, kế toán...). Không có quyền thì tab ẩn.
const List<AppMenuItem> managerTabs = <AppMenuItem>[
  AppMenuItem(
    label: 'Trang chủ',
    icon: Icons.home_outlined,
    path: '/dashboard',
    anyOf: <String>['Reports.ViewOperations', 'Reports.ViewFinance'],
  ),
  AppMenuItem(
    label: 'Đơn hàng',
    icon: Icons.receipt_long_outlined,
    path: '/orders',
    anyOf: <String>['Orders.View'],
  ),
  AppMenuItem(
    label: 'Đội xe',
    icon: Icons.local_shipping_outlined,
    path: '/fleet',
    anyOf: <String>['Vehicles.View'],
  ),
  AppMenuItem(
    label: 'Bảo trì',
    icon: Icons.build_outlined,
    path: '/maintenance',
    anyOf: <String>['Vehicles.View', 'Vehicles.Maintenance'],
  ),
];

// Tab cuối của quản lý: mở màn Thêm
const AppMenuItem moreTab = AppMenuItem(
  label: 'Thêm',
  icon: Icons.more_horiz,
  path: '/more',
);

// Tab của tài xế (không có quyền quản lý nào): chỉ việc của mình
// Tên tab theo ngôn ngữ máy nên là getter (t() không dùng được trong const)
List<AppMenuItem> get driverTabs => <AppMenuItem>[
  // Biểu tượng đặc như thanh tab App Store iOS 26 (đang chọn đổi màu xanh, không đổi hình)
  AppMenuItem(label: t('tabs.trips'), icon: CupertinoIcons.map_fill, selectedIcon: CupertinoIcons.map_fill, path: '/driver/trips'),
  AppMenuItem(
    label: t('tabs.breakdowns'),
    icon: CupertinoIcons.exclamationmark_triangle_fill,
    selectedIcon: CupertinoIcons.exclamationmark_triangle_fill,
    path: '/driver/breakdowns',
  ),
  AppMenuItem(
    label: t('tabs.account'),
    icon: CupertinoIcons.person_crop_circle_fill,
    selectedIcon: CupertinoIcons.person_crop_circle_fill,
    path: '/more',
  ),
];

// Nhóm "Quản lý" trong màn Thêm
const List<AppMenuItem> moreItems = <AppMenuItem>[
  AppMenuItem(
    label: 'Điều phối hôm nay',
    icon: Icons.place_outlined,
    path: '/dispatch/today',
    anyOf: <String>['Orders.View'],
  ),
  AppMenuItem(
    label: 'Khách hàng',
    icon: Icons.contacts_outlined,
    path: '/customers',
    anyOf: <String>['Customers.View'],
  ),
  AppMenuItem(
    label: 'Nhân sự',
    icon: Icons.groups_outlined,
    path: '/staff',
    anyOf: <String>['Users.View'],
  ),
  AppMenuItem(
    label: 'Phân quyền',
    icon: Icons.verified_user_outlined,
    path: '/roles',
    // Doc mục 3.10: xem được khi có Users.View; nút đổi vai trò mới cần Users.ManageRoles
    anyOf: <String>['Users.View'],
  ),
  AppMenuItem(
    label: 'Báo hỏng xe',
    icon: Icons.warning_amber_outlined,
    path: '/maintenance/breakdowns',
    anyOf: <String>['Orders.View'],
  ),
  AppMenuItem(
    label: 'Cảnh báo giấy tờ',
    icon: Icons.notifications_none,
    path: '/dashboard/alerts',
    anyOf: <String>['Users.ManageComplianceDocs', 'Reports.ViewOperations'],
  ),
  AppMenuItem(
    label: 'Doanh thu',
    icon: Icons.bar_chart,
    path: '/dashboard/revenue',
    anyOf: <String>['Reports.ViewFinance'],
  ),
  // Ai cũng có thể được giao chuyến (doc mục 2.8: luôn hiện)
  AppMenuItem(label: 'Chuyến của tôi', icon: Icons.route_outlined, path: '/driver/trips'),
];

// Không được xem tab quản lý nào thì dùng menu tài xế
bool usesDriverMenu(Session session) {
  for (final AppMenuItem tab in managerTabs) {
    if (tab.isVisibleFor(session)) {
      return false;
    }
  }
  return true;
}

// Thanh tab của người này
List<AppMenuItem> tabsFor(Session session) {
  if (usesDriverMenu(session)) {
    return driverTabs;
  }
  final List<AppMenuItem> tabs = <AppMenuItem>[];
  for (final AppMenuItem tab in managerTabs) {
    if (tab.isVisibleFor(session)) {
      tabs.add(tab);
    }
  }
  tabs.add(moreTab);
  return tabs;
}

// Các mục nhóm "Quản lý" người này được thấy
List<AppMenuItem> moreItemsFor(Session session) {
  final List<AppMenuItem> items = <AppMenuItem>[];
  for (final AppMenuItem item in moreItems) {
    // Tài xế đã có tab "Chuyến của tôi" ở thanh dưới, không lặp lại ở đây
    if (item.path == '/driver/trips' && usesDriverMenu(session)) {
      continue;
    }
    if (item.isVisibleFor(session)) {
      items.add(item);
    }
  }
  return items;
}
