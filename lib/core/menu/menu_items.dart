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
  // Biểu tượng tô đặc khi tab đang chọn
  final IconData? selectedIcon;
  final String path;
  // Tên SF Symbol cho thanh tab native trên iOS
  final String? sfSymbol;
  //Có ít nhất 1 quyền trong danh sách thì hiện. Danh sách rỗng thì ai cũng thấy.
  final List<String> anyOf;

  const AppMenuItem({
    required this.label,
    required this.icon,
    this.selectedIcon,
    required this.path,
    this.sfSymbol,
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
// Tên tab theo ngôn ngữ máy nên là getter (t() không dùng được trong const)
List<AppMenuItem> get managerTabs => <AppMenuItem>[
  AppMenuItem(
    label: t('tabs.home'),
    icon: CupertinoIcons.house_fill,
    selectedIcon: CupertinoIcons.house_fill,
    sfSymbol: 'house.fill',
    path: '/dashboard',
    anyOf: const <String>['Reports.ViewOperations', 'Reports.ViewFinance'],
  ),
  AppMenuItem(
    label: t('tabs.orders'),
    icon: CupertinoIcons.doc_text_fill,
    selectedIcon: CupertinoIcons.doc_text_fill,
    sfSymbol: 'doc.text.fill',
    path: '/orders',
    anyOf: const <String>['Orders.View'],
  ),
  AppMenuItem(
    label: t('tabs.fleet'),
    icon: Icons.local_shipping,
    selectedIcon: Icons.local_shipping,
    sfSymbol: 'truck.box.fill',
    path: '/fleet',
    anyOf: const <String>['Vehicles.View'],
  ),
  AppMenuItem(
    label: t('tabs.maintenance'),
    icon: CupertinoIcons.wrench_fill,
    selectedIcon: CupertinoIcons.wrench_fill,
    sfSymbol: 'wrench.fill',
    path: '/maintenance',
    anyOf: const <String>['Vehicles.View', 'Vehicles.Maintenance'],
  ),
];

// Tab cuối của quản lý: mở màn Thêm
AppMenuItem get moreTab => AppMenuItem(
  label: t('tabs.more'),
  icon: CupertinoIcons.ellipsis_circle_fill,
  selectedIcon: CupertinoIcons.ellipsis_circle_fill,
  sfSymbol: 'ellipsis.circle.fill',
  path: '/more',
);

// Tab của tài xế (không có quyền quản lý nào): chỉ việc của mình
// Tên tab theo ngôn ngữ máy nên là getter (t() không dùng được trong const)
List<AppMenuItem> get driverTabs => <AppMenuItem>[
  // Biểu tượng đặc như thanh tab App Store iOS 26 (đang chọn đổi màu xanh, không đổi hình)
  AppMenuItem(label: t('tabs.trips'), icon: CupertinoIcons.map_fill, selectedIcon: CupertinoIcons.map_fill, sfSymbol: 'map.fill', path: '/driver/trips'),
  AppMenuItem(
    label: t('tabs.breakdowns'),
    icon: CupertinoIcons.exclamationmark_triangle_fill,
    selectedIcon: CupertinoIcons.exclamationmark_triangle_fill,
    sfSymbol: 'exclamationmark.triangle.fill',
    path: '/driver/breakdowns',
  ),
  AppMenuItem(
    label: t('tabs.account'),
    icon: CupertinoIcons.person_crop_circle_fill,
    selectedIcon: CupertinoIcons.person_crop_circle_fill,
    sfSymbol: 'person.crop.circle.fill',
    path: '/more',
  ),
];

// Nhóm "Quản lý" trong màn Thêm
// Tên theo ngôn ngữ máy nên là getter
List<AppMenuItem> get moreItems => <AppMenuItem>[
  AppMenuItem(
    label: t('more.dispatchToday'),
    icon: Icons.place_outlined,
    path: '/dispatch/today',
    anyOf: const <String>['Orders.View'],
  ),
  AppMenuItem(
    label: t('more.customers'),
    icon: Icons.contacts_outlined,
    path: '/customers',
    anyOf: const <String>['Customers.View'],
  ),
  AppMenuItem(
    label: t('more.staff'),
    icon: Icons.groups_outlined,
    path: '/staff',
    anyOf: const <String>['Users.View'],
  ),
  AppMenuItem(
    label: t('more.roles'),
    icon: Icons.verified_user_outlined,
    path: '/roles',
    // Doc mục 3.10: xem được khi có Users.View; nút đổi vai trò mới cần Users.ManageRoles
    anyOf: const <String>['Users.View'],
  ),
  AppMenuItem(
    label: t('more.breakdowns'),
    icon: Icons.warning_amber_outlined,
    path: '/maintenance/breakdowns',
    anyOf: const <String>['Orders.View'],
  ),
  AppMenuItem(
    label: t('more.documentAlerts'),
    icon: Icons.notifications_none,
    path: '/dashboard/alerts',
    anyOf: const <String>['Users.ManageComplianceDocs', 'Reports.ViewOperations'],
  ),
  AppMenuItem(
    label: t('more.revenue'),
    icon: Icons.bar_chart,
    path: '/dashboard/revenue',
    anyOf: const <String>['Reports.ViewFinance'],
  ),
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
    if (item.isVisibleFor(session)) {
      items.add(item);
    }
  }
  return items;
}
