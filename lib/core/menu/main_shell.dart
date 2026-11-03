// Khung chính sau khi đăng nhập: màn đang mở ở trên, thanh tab theo quyền ở dưới.
// Mọi màn của cả nhóm (trừ đăng nhập, đổi mật khẩu) nằm trong khung này.
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;
import 'package:flutter/material.dart';
// Riverpod: ConsumerWidget, WidgetRef
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.go
import 'package:go_router/go_router.dart';

import '../../features/auth/session_provider.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import '../widgets/ios.dart';
import 'menu_items.dart';
import '../i18n.dart';

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
    final bool fullScreen = isFullScreenDriverTask(location);

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

    return _shell(context, tabs, selectedIndex, fullScreen);
  }
}

// Mọi vai trò dùng chung thanh tab kính nổi (iOS 26 Liquid Glass), nội dung mọi trang chạy xuống dưới thanh.
// Thanh tab thu nhỏ khi cuộn nội dung lên (kéo danh sách / kéo sheet lên), như thanh tab iOS 26.
// Cuộn xuống lại hoặc về đầu trang thì nở ra.
class TabBarCompactNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  // Sheet bản đồ đang kéo lên cao: cuộn về đầu danh sách trong sheet không được làm thanh nở ra
  bool sheetRaised = false;

  void set(bool value) {
    if (state != value) state = value;
  }

  // Đổi tab: màn mới không có sheet đang kéo lên
  void reset() {
    sheetRaised = false;
    set(false);
  }
}

final tabBarCompactProvider = NotifierProvider<TabBarCompactNotifier, bool>(TabBarCompactNotifier.new);

/// Nghe cuộn của màn bên trong để thu / nở thanh tab
class _ScrollCompactor extends ConsumerWidget {
  final Widget child;

  const _ScrollCompactor({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TabBarCompactNotifier compact = ref.read(tabBarCompactProvider.notifier);
    return NotificationListener<Notification>(
      onNotification: (Notification notification) {
        if (notification is DraggableScrollableNotification) {
          // Kéo sheet bản đồ lên gần hết thì thu nhỏ
          compact.sheetRaised = notification.extent > 0.6;
          compact.set(compact.sheetRaised);
        } else if (notification is ScrollUpdateNotification && notification.metrics.axis == Axis.vertical) {
          final double delta = notification.scrollDelta ?? 0;
          if (notification.metrics.pixels <= 8) {
            compact.set(compact.sheetRaised);
          } else if (delta > 2) {
            compact.set(true);
          } else if (delta < -6) {
            compact.set(compact.sheetRaised);
          }
        }
        return false;
      },
      child: child,
    );
  }
}

class _CompactTabBar extends ConsumerWidget {
  final List<GlassTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _CompactTabBar({required this.items, required this.selectedIndex, required this.onSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool compact = ref.watch(tabBarCompactProvider);
    if (useNativeControls) {
      // Thanh tab kính của gói liquid_glass_widgets, thu về viên của tab đang chọn khi cuộn như iOS 26.
      // Nằm trên bản đồ nên cần platformViewBackdrop để làm mờ được
      return lg.GlassTabBar.minimizable(
        minimized: compact,
        onMinimizedTabTap: () => ref.read(tabBarCompactProvider.notifier).set(false),
        horizontalPadding: 24,
        verticalPadding: 0,
        barHeight: GlassTabBar.barHeight,
        platformViewBackdrop: true,
        // Trên view native phần kính không lấy được màu nền nên mặc định tô đen (vạch đen lúc giữ).
        // passthrough: chỗ không lấy được màu thì để trong suốt, thấy phần phía sau
        indicatorSettings: const lg.LiquidGlassSettings(platformViewMode: lg.PlatformViewGlassMode.passthrough),
        selectedIconColor: AppColors.navy,
        selectedLabelColor: AppColors.navy,
        selectedIndex: selectedIndex,
        onTabSelected: (int index) {
          ref.read(tabBarCompactProvider.notifier).reset();
          onSelected(index);
        },
        tabs: <lg.GlassTab>[
          for (final GlassTabItem item in items)
            lg.GlassTab(icon: Icon(item.icon), activeIcon: Icon(item.selectedIcon), label: item.label),
        ],
      );
    }
    // Giữ chiều cao cố định: thanh co lại trong khung này, nội dung phía trên không phải tính lại bố cục theo từng frame
    return SizedBox(
      height: GlassTabBar.barHeight,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          // Thu nhỏ: hẹp lại hai bên một chút
          padding: EdgeInsets.symmetric(horizontal: compact ? 48 : 24),
          child: GlassTabBar(
            items: items,
            selectedIndex: selectedIndex,
            compact: compact,
            onSelected: (int index) {
              ref.read(tabBarCompactProvider.notifier).reset();
              onSelected(index);
            },
          ),
        ),
      ),
    );
  }
}

/// Đưa thanh tab trượt xuống khuất khi mở màn toàn màn hình, trượt lên lại khi quay về.
/// Khuất rồi thì thôi vẽ nhưng vẫn giữ chỗ: chiều cao thanh không đổi nên trang bên trong không phải tính lại bố cục.
class _TabBarSlide extends StatefulWidget {
  final bool hidden;
  final Widget child;

  const _TabBarSlide({required this.hidden, required this.child});

  @override
  State<_TabBarSlide> createState() => _TabBarSlideState();
}

class _TabBarSlideState extends State<_TabBarSlide> with SingleTickerProviderStateMixin {
  late final AnimationController hide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: widget.hidden ? 1 : 0,
  );
  late final Animation<Offset> offset = Tween<Offset>(begin: Offset.zero, end: const Offset(0, 1.4))
      .animate(CurvedAnimation(parent: hide, curve: Curves.easeOutCubic));

  @override
  void didUpdateWidget(covariant _TabBarSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hidden == widget.hidden) return;
    if (widget.hidden) {
      hide.forward();
    } else {
      hide.reverse();
    }
  }

  @override
  void dispose() {
    hide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: hide,
      builder: (BuildContext context, Widget? bar) {
        return Visibility(
          visible: !hide.isCompleted,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: true,
          child: bar!,
        );
      },
      child: IgnorePointer(
        ignoring: widget.hidden,
        child: SlideTransition(position: offset, child: widget.child),
      ),
    );
  }
}

extension on MainShell {
  // Màn toàn màn hình vẫn đi qua đây, chỉ giấu thanh tab: giữ nguyên cây widget thì đổi màn không phải dựng lại cả Navigator
  Widget _shell(BuildContext context, List<AppMenuItem> tabs, int selectedIndex, bool hideTabBar) {
    final List<GlassTabItem> items = <GlassTabItem>[];
    for (final AppMenuItem tab in tabs) {
      items.add(GlassTabItem(icon: tab.icon, selectedIcon: tab.selectedIcon ?? tab.icon, label: tab.label, sfSymbol: tab.sfSymbol));
    }
    return Scaffold(
      // Mọi trang chạy xuống dưới thanh tab kính. Trang tự chừa khoảng đáy theo MediaQuery.padding (xem withTabBarInset)
      extendBody: true,
      body: _ScrollCompactor(child: child),
      bottomNavigationBar: _TabBarSlide(
        hidden: hideTabBar,
        child: Stack(
          children: <Widget>[
            // Nội dung chạy dưới thanh tab thì mờ dần về phía đáy (progressive blur), như iOS 26
            Positioned.fill(
              child: ProgressiveBlur(height: double.infinity, fromTop: false, maxSigma: 6, tintOpacity: 0),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.only(top: 24),
                child: _CompactTabBar(
                  items: items,
                  selectedIndex: selectedIndex,
                  onSelected: (int index) {
                    context.go(tabs[index].path);
                  },
                ),
              ),
            ),
          ],
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
  return location.startsWith('/driver/trips/') || location == '/driver/location-consent' || location.startsWith('/orders/new') || (location.startsWith('/orders/') && location.endsWith('/edit'));
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
            t('ui.pageNotFound'),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
