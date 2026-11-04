// B1: trang chủ quản lý. Ảnh bìa mờ dần vào nền, avatar có vòng tỉ lệ xe sẵn sàng, ba con số chính, phím tắt,
// rồi việc cần xử lý, đội xe, hôm nay, tiền tháng. Khối tiền ẩn hẳn khi finance = null (vd điều phối).
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/labels.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ios.dart';
import '../../core/widgets/liftmate_intelligence.dart';
import '../../core/widgets/page_transition.dart';
import '../../core/widgets/user_avatar.dart';
import '../auth/session_provider.dart';
import '../orders/order_ai_screen.dart' show orderAiDisabled;
import 'bing_wallpaper.dart';
import 'dashboard_api.dart';
import 'home_cover.dart';
import 'home_tasks.dart';

const FlutterSecureStorage _storage = FlutterSecureStorage();
const String _hideMoneyKey = 'home_hide_money';
const int _maxTasks = 5;

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  static const double barHeight = 56;
  final ScrollController scroll = ScrollController();
  final ValueNotifier<double> offset = ValueNotifier<double>(0);
  File? coverImage;
  bool hideMoney = false;
  late final AppLifecycleListener lifecycle;

  @override
  void initState() {
    super.initState();
    // Quay lại app thì xem Bing đã đổi ảnh chưa; chưa tới giờ đổi thì không gọi mạng
    lifecycle = AppLifecycleListener(onResume: loadCover);
    scroll.addListener(() => offset.value = scroll.offset);
    coverImage = HomeCoverStore.lastResolved(ref.read(sessionProvider).value?.userId ?? '');
    loadPreferences();
  }

  /// Hiện ngay ảnh đã có; đang dùng Bing thì kiểm tra ảnh mới ở nền, lỗi mạng thì giữ ảnh cũ
  Future<void> loadCover() async {
    final String? userId = ref.read(sessionProvider).value?.userId;
    if (userId == null || userId.isEmpty) return;
    final File? image = await HomeCoverStore.resolve(userId);
    if (mounted && image?.path != coverImage?.path) setState(() => coverImage = image);
    if (await HomeCoverStore.source(userId) != HomeCoverSource.bing) return;
    try {
      final BingCover? latest = await BingWallpaper.refresh();
      if (mounted && latest != null && latest.image.path != coverImage?.path) setState(() => coverImage = latest.image);
    } catch (error) {
      debugPrint('Không cập nhật được ảnh Bing: $error');
    }
  }

  Future<void> loadPreferences() async {
    loadCover();
    String? hidden;
    try {
      hidden = await _storage.read(key: _hideMoneyKey);
    } catch (error) {
      debugPrint('Không đọc được cài đặt che số tiền: $error');
    }
    if (mounted) {
      setState(() => hideMoney = hidden == '1');
    }
  }

  @override
  void dispose() {
    lifecycle.dispose();
    scroll.dispose();
    offset.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    try {
      ref.invalidate(dashboardSummaryProvider);
      await ref.read(dashboardSummaryProvider.future);
    } catch (error) {
      // Giữ số đang hiện, chỉ báo là chưa cập nhật được
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  void toggleMoney() {
    setState(() => hideMoney = !hideMoney);
    _storage.write(key: _hideMoneyKey, value: hideMoney ? '1' : '0').catchError((Object error) {
      debugPrint('Không lưu được cài đặt che số tiền: $error');
    });
  }

  Future<void> openAppearance() async {
    await context.push('/dashboard/appearance');
    if (mounted) loadCover();
  }

  @override
  Widget build(BuildContext context) {
    final Session? session = ref.watch(sessionProvider).value;
    final bool canOperations = session?.can('Reports.ViewOperations') ?? false;
    final AsyncValue<DashboardSummary>? value = canOperations ? ref.watch(dashboardSummaryProvider) : null;
    final DashboardSummary? summary = value?.value;
    final double top = MediaQuery.paddingOf(context).top;
    final double coverHeight = top + 340;

    return Scaffold(
      backgroundColor: IosColors.groupedBackground,
      body: Stack(
        children: <Widget>[
          HomeCover(image: coverImage, height: coverHeight, offset: offset),
          Positioned.fill(
            child: CustomScrollView(
              controller: scroll,
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              slivers: <Widget>[
                SliverToBoxAdapter(child: SizedBox(height: top + barHeight)),
                if (canOperations) CupertinoSliverRefreshControl(onRefresh: refresh),
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const SizedBox(height: 84),
                      _Hero(session: session, summary: summary, loading: canOperations && summary == null && !(value?.hasError ?? false)),
                      if (canOperations) ...<Widget>[
                        const SizedBox(height: 18),
                        _BigStats(session: session, summary: summary),
                      ],
                      const SizedBox(height: 18),
                      _QuickActions(session: session),
                      const SizedBox(height: 22),
                      ...sections(session, value, summary, canOperations),
                      Align(
                        widthFactor: 1,
                        child: IosPressBounce(
                          child: GestureDetector(
                            onTap: openAppearance,
                            child: Semantics(
                              button: true,
                              child: Container(
                                height: 44,
                                padding: const EdgeInsets.symmetric(horizontal: 26),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(color: IosColors.separator),
                                ),
                                child: Center(
                                  widthFactor: 1,
                                  child: Text(t('home.appearance'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
                SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 16)),
              ],
            ),
          ),
          _TopBar(
            top: top,
            height: barHeight,
            fadeStart: coverHeight * 0.42,
            offset: offset,
            alertCount: summary?.urgentAlerts.length ?? 0,
            showIntelligence: session?.can('Orders.Create') ?? false,
            showAlerts: canOperations,
          ),
        ],
      ),
    );
  }

  List<Widget> sections(Session? session, AsyncValue<DashboardSummary>? value, DashboardSummary? summary, bool canOperations) {
    if (!canOperations) {
      // Chỉ có quyền tài chính: không gọi được summary, đưa sang Doanh thu
      return <Widget>[
        IosGroup(
          children: <Widget>[
            IosRow(
              icon: CupertinoIcons.chart_bar_alt_fill,
              iconColor: const Color(0xFFAF52DE),
              title: t('home.revenue'),
              onTap: () => context.push('/dashboard/revenue'),
            ),
          ],
        ),
      ];
    }
    if (summary == null) {
      if (value?.hasError ?? false) {
        return <Widget>[
          IosGroup(
            footer: errorMessage(value!.error!),
            children: <Widget>[
              IosRow(icon: CupertinoIcons.refresh, iconColor: AppColors.navy, title: t('common.retry'), onTap: () => ref.invalidate(dashboardSummaryProvider)),
            ],
          ),
        ];
      }
      return const <Widget>[_SkeletonGroup(rows: 3), _SkeletonGroup(rows: 2), _SkeletonGroup(rows: 2)];
    }
    return <Widget>[
      _TasksGroup(session: session, summary: summary),
      _FleetGroup(session: session, summary: summary),
      _TodayGroup(session: session, summary: summary),
      if (summary.finance != null) _FinanceGroup(finance: summary.finance!, hidden: hideMoney, onToggle: toggleMoney),
    ];
  }
}

class _TopBar extends StatelessWidget {
  final double top;
  final double height;
  final double fadeStart;
  final ValueNotifier<double> offset;
  final int alertCount;
  final bool showIntelligence;
  final bool showAlerts;

  const _TopBar({
    required this.top,
    required this.height,
    required this.fadeStart,
    required this.offset,
    required this.alertCount,
    required this.showIntelligence,
    required this.showAlerts,
  });

  @override
  Widget build(BuildContext context) {
    final Color background = IosColors.groupedBackground;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      height: top + height + 24,
      child: Stack(
        children: <Widget>[
          // Cuộn qua ảnh bìa thì thanh trên đục dần, hiện tiêu đề nhỏ
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: offset,
                builder: (BuildContext context, Widget? child) => Opacity(
                  opacity: ((offset.value - fadeStart) / 40).clamp(0.0, 1.0),
                  child: child,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: <double>[0, (top + height) / (top + height + 24), 1],
                      colors: <Color>[background, background, background.withValues(alpha: 0)],
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(top: top, bottom: 24),
                    child: Center(
                      child: Text(t('tabs.home'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text)),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: top,
            height: height,
            child: Row(
              children: <Widget>[
                const Spacer(),
                if (showIntelligence)
                  ValueListenableBuilder<bool>(
                    valueListenable: orderAiDisabled,
                    builder: (BuildContext context, bool disabled, Widget? child) => disabled
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: AiOrbButton(onPressed: () => context.push('/orders/new/ai?then=form')),
                          ),
                  ),
                if (showAlerts)
                  Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      IosGlassIconButton(icon: CupertinoIcons.bell_fill, nativeSymbol: 'bell.fill', tooltip: t('home.alerts'), onPressed: () => context.push('/dashboard/alerts')),
                      if (alertCount > 0)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: IgnorePointer(
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 20),
                              height: 20,
                              padding: const EdgeInsets.symmetric(horizontal: 5),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: IosColors.red, borderRadius: BorderRadius.circular(10)),
                              child: Text('$alertCount', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final Session? session;
  final DashboardSummary? summary;
  final bool loading;

  const _Hero({required this.session, required this.summary, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  t('home.greeting', <String, Object?>{'name': session?.fullName ?? ''}),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 30, height: 1.12, fontWeight: FontWeight.w700, letterSpacing: -0.7, color: AppColors.text),
                ),
                const SizedBox(height: 6),
                Text(
                  '${session?.companyName ?? ''} · ${dateFormat.format(DateTime.now())}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: IosColors.secondaryLabel),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IosPressBounce(
            child: GestureDetector(
              onTap: () => context.push('/account/profile'),
              child: Semantics(
                button: true,
                label: summary == null || fleetReadiness(summary!) == null
                    ? session?.fullName
                    : t('home.readinessLabel', <String, Object?>{'percent': (fleetReadiness(summary!)! * 100).round()}),
                child: _ReadinessAvatar(name: session?.fullName ?? '', url: session?.avatarUrl, readiness: summary == null ? null : fleetReadiness(summary!)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Avatar có vòng cho biết tỉ lệ xe sẵn sàng: xanh khi ổn, cam rồi đỏ khi nhiều xe không chạy được
class _ReadinessAvatar extends StatelessWidget {
  static const double size = 84;
  final String name;
  final String? url;
  final double? readiness;

  const _ReadinessAvatar({required this.name, required this.url, required this.readiness});

  static Color colorFor(double value) {
    if (value >= 0.7) return IosColors.green;
    if (value >= 0.4) return IosColors.orange;
    return IosColors.red;
  }

  @override
  Widget build(BuildContext context) {
    final double? value = readiness;
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: value ?? 0),
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (BuildContext context, double animated, Widget? child) => CustomPaint(
          painter: _RingPainter(
            value: animated,
            color: value == null ? IosColors.separator : colorFor(value),
            track: IosColors.fill,
          ),
          child: child,
        ),
        child: Center(child: UserAvatar(name: name, url: url, size: size - 14)),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color color;
  final Color track;

  const _RingPainter({required this.value, required this.color, required this.track});

  static const double stroke = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    if (value <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => oldDelegate.value != value || oldDelegate.color != color || oldDelegate.track != track;
}

class _BigStats extends StatelessWidget {
  final Session? session;
  final DashboardSummary? summary;

  const _BigStats({required this.session, required this.summary});

  @override
  Widget build(BuildContext context) {
    final DashboardSummary? data = summary;
    String number(int Function(DashboardSummary) read) => data == null ? '–' : formatNumber(read(data));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: <Widget>[
          _BigStat(
            value: number((DashboardSummary s) => s.count(s.fleet, 'availableCount')),
            label: t('home.ready'),
            onTap: (session?.can('Vehicles.View') ?? false) ? () => pushTabRoot(context, '/fleet') : null,
          ),
          _BigStat(
            value: number((DashboardSummary s) => s.count(s.today, 'tripsToday')),
            label: t('home.tripsToday'),
            onTap: (session?.can('Orders.View') ?? false) ? () => context.push('/dispatch/today') : null,
          ),
          _BigStat(
            value: number((DashboardSummary s) => s.count(s.orders, 'activeOrdersCount')),
            label: t('home.activeOrders'),
            onTap: (session?.can('Orders.View') ?? false) ? () => pushTabRoot(context, '/orders') : null,
          ),
        ],
      ),
    );
  }
}

class _BigStat extends StatelessWidget {
  final String value;
  final String label;
  final VoidCallback? onTap;

  const _BigStat({required this.value, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(value, style: TextStyle(fontSize: 26, height: 1.15, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: AppColors.text)),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel)),
      ],
    );
    return Expanded(
      child: onTap == null
          ? content
          : IosPressBounce(
              child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: Semantics(button: true, child: content)),
            ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final Session? session;

  const _QuickActions({required this.session});

  @override
  Widget build(BuildContext context) {
    bool can(String permission) => session?.can(permission) ?? false;
    final List<Widget> chips = <Widget>[
      if (can('Orders.Create'))
        _ActionChip(
          primary: true,
          leading: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[Color.lerp(AppColors.navy, Colors.white, 0.18)!, AppColors.navy],
              ),
            ),
            child: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
          ),
          label: Text(t('home.createOrder'), style: _ActionChip.textStyle.copyWith(color: AppColors.navy)),
          onTap: () => context.push('/orders/new'),
        ),
      if (can('Orders.Create'))
        ValueListenableBuilder<bool>(
          valueListenable: orderAiDisabled,
          builder: (BuildContext context, bool disabled, Widget? child) => disabled ? const SizedBox.shrink() : child!,
          child: _ActionChip(
            leading: const AiOrb(size: 20),
            label: AiGradient(child: Text(AiBrandText.brand, style: aiTextStyle(15, fontWeight: FontWeight.w600))),
            onTap: () => context.push('/orders/new/ai?then=form'),
          ),
        ),
      if (can('Orders.View'))
        _ActionChip(
          leading: const Icon(CupertinoIcons.map_fill, size: 19, color: Color(0xFF007AFF)),
          label: Text(t('home.dispatch'), style: _ActionChip.textStyle),
          onTap: () => context.push('/dispatch/today'),
        ),
      if (can('Reports.ViewFinance'))
        _ActionChip(
          leading: const Icon(CupertinoIcons.chart_bar_alt_fill, size: 19, color: Color(0xFFAF52DE)),
          label: Text(t('home.revenue'), style: _ActionChip.textStyle),
          onTap: () => context.push('/dashboard/revenue'),
        ),
      if (can('Reports.ViewOperations') || can('Users.ManageComplianceDocs'))
        _ActionChip(
          leading: Icon(CupertinoIcons.doc_on_doc_fill, size: 18, color: IosColors.orange),
          label: Text(t('home.documents'), style: _ActionChip.textStyle),
          onTap: () => context.push('/dashboard/alerts'),
        ),
      if (can('Customers.View'))
        _ActionChip(
          leading: const Icon(CupertinoIcons.person_2_fill, size: 19, color: Color(0xFF30B0C7)),
          label: Text(t('home.customers'), style: _ActionChip.textStyle),
          onTap: () => context.push('/customers'),
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // Để bóng của nút Tạo đơn không bị cắt ở mép trên, dưới
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (BuildContext context, int index) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) => chips[index],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  static TextStyle get textStyle => TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text);

  final Widget leading;
  final Widget label;
  final VoidCallback onTap;
  // Việc chính của trang chủ (Tạo đơn): vẫn nền trắng như các nút khác, có bóng nhẹ để nổi hơn một chút
  final bool primary;

  const _ActionChip({required this.leading, required this.label, required this.onTap, this.primary = false});

  @override
  Widget build(BuildContext context) {
    return IosPressBounce(
      child: GestureDetector(
        onTap: onTap,
        child: Semantics(
          button: true,
          child: Container(
            padding: EdgeInsets.only(left: primary ? 10 : 14, right: primary ? 16 : 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(22),
              boxShadow: primary
                  ? <BoxShadow>[BoxShadow(color: AppColors.navy.withValues(alpha: 0.14), blurRadius: 12, offset: const Offset(0, 4))]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[leading, const SizedBox(width: 7), label],
            ),
          ),
        ),
      ),
    );
  }
}

class _TasksGroup extends StatelessWidget {
  final Session? session;
  final DashboardSummary summary;

  const _TasksGroup({required this.session, required this.summary});

  Widget documentPill(int days) {
    if (days < 0) return IosPill(t('home.expiredDays', <String, Object?>{'days': -days}), color: IosColors.red);
    if (days == 0) return IosPill(t('home.expiredToday'), color: IosColors.red);
    if (days <= 3) return IosPill(t('home.daysLeft', <String, Object?>{'days': days}), color: IosColors.red);
    return IosPill(t('home.daysLeft', <String, Object?>{'days': days}), color: IosColors.orange);
  }

  Widget row(BuildContext context, HomeTask task) {
    final bool canVehicles = session?.can('Vehicles.View') ?? false;
    final bool canOrders = session?.can('Orders.View') ?? false;
    switch (task.kind) {
      case HomeTaskKind.document:
        final VehicleAlert alert = task.alert!;
        return IosRow(
          title: alert.plateNumber,
          subtitle: <String>[
            label(vehicleDocumentLabels, alert.documentType),
            if (alert.blocksCapability != null) alert.daysRemaining < 0 ? t('home.cannotRun') : t('home.willBlock'),
          ].join(' · '),
          trailing: documentPill(alert.daysRemaining),
          onTap: canVehicles ? () => context.push('/fleet/${alert.vehiclePublicId}') : null,
        );
      case HomeTaskKind.finalize:
        return IosRow(
          icon: CupertinoIcons.checkmark_seal_fill,
          iconColor: const Color(0xFF8944AB),
          title: t('home.awaitingFinalization', <String, Object?>{'count': task.count}),
          onTap: canOrders ? () => pushTabRoot(context, '/orders') : null,
        );
      case HomeTaskKind.invoice:
        return IosRow(
          icon: CupertinoIcons.doc_text_fill,
          iconColor: const Color(0xFF00817A),
          title: t('home.awaitingInvoice', <String, Object?>{'count': task.count}),
          onTap: canOrders ? () => pushTabRoot(context, '/orders') : null,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<HomeTask> tasks = homeTasks(summary);
    return IosGroup(
      header: t('home.tasks'),
      headerIcon: CupertinoIcons.exclamationmark_circle_fill,
      children: <Widget>[
        if (tasks.isEmpty)
          IosRow(icon: CupertinoIcons.checkmark_alt, iconColor: IosColors.green, title: t('home.allGood'), chevron: false),
        for (final HomeTask task in tasks.take(_maxTasks)) row(context, task),
        if (tasks.length > _maxTasks)
          IosRow(title: t('home.seeAll', <String, Object?>{'count': tasks.length}), onTap: () => context.push('/dashboard/alerts')),
      ],
    );
  }
}

class _FleetGroup extends StatelessWidget {
  final Session? session;
  final DashboardSummary summary;

  const _FleetGroup({required this.session, required this.summary});

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> fleet = summary.fleet;
    final List<(int, String, Color)> parts = <(int, String, Color)>[
      (summary.count(fleet, 'availableCount'), t('home.ready'), IosColors.green),
      (summary.count(fleet, 'inUseCount'), t('home.inUse'), const Color(0xFF0A84FF)),
      (summary.count(fleet, 'maintenanceCount'), t('home.maintenance'), IosColors.orange),
      (summary.count(fleet, 'suspendedCount'), t('home.suspended'), const Color(0xFFAF52DE)),
      (summary.count(fleet, 'notRoadworthyCount'), t('home.notRoadworthy'), IosColors.red),
    ];
    final num? utilization = fleet['utilizationThisMonthPercent'] as num?;
    final String header = utilization == null
        ? t('home.fleetHeader', <String, Object?>{'count': summary.count(fleet, 'totalVehicles')})
        : t('home.fleetHeaderUse', <String, Object?>{'count': summary.count(fleet, 'totalVehicles'), 'percent': utilization.round()});
    final Widget body = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(
                children: <Widget>[
                  for (final (int count, String _, Color color) in parts)
                    if (count > 0)
                      Expanded(
                        flex: count,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          color: color,
                        ),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: <Widget>[
              for (final (int count, String name, Color color) in parts)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text('$count', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
                    const SizedBox(width: 3),
                    Text(name, style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
    return IosGroup(
      header: header,
      headerIcon: Icons.local_shipping,
      children: <Widget>[
        (session?.can('Vehicles.View') ?? false)
            ? Material(
                color: AppColors.surface,
                child: InkWell(highlightColor: IosColors.fill, splashFactory: NoSplash.splashFactory, onTap: () => pushTabRoot(context, '/fleet'), child: body),
              )
            : body,
      ],
    );
  }
}

class _TodayGroup extends StatelessWidget {
  final Session? session;
  final DashboardSummary summary;

  const _TodayGroup({required this.session, required this.summary});

  @override
  Widget build(BuildContext context) {
    return IosGroup(
      header: t('home.today'),
      headerIcon: CupertinoIcons.sun_max_fill,
      dividerIndent: 62,
      children: <Widget>[
        IosRow(
          icon: CupertinoIcons.location_fill,
          iconColor: const Color(0xFF0A84FF),
          title: t('home.vehiclesOnTrip'),
          value: '${summary.count(summary.today, 'vehiclesOnTripNow')}',
          onTap: (session?.can('Orders.View') ?? false) ? () => context.push('/dispatch/today') : null,
        ),
        IosRow(
          icon: CupertinoIcons.person_2_fill,
          iconColor: const Color(0xFF30B0C7),
          title: t('home.crewWorking'),
          value: '${summary.count(summary.today, 'crewWorkingToday')}',
          chevron: false,
        ),
      ],
    );
  }
}

class _FinanceGroup extends StatelessWidget {
  final FinanceSummary finance;
  final bool hidden;
  final VoidCallback onToggle;

  const _FinanceGroup({required this.finance, required this.hidden, required this.onToggle});

  String money(num value) => hidden ? '••••••' : formatMoney(value);

  @override
  Widget build(BuildContext context) {
    return IosGroup(
      header: t('home.moneyMonth', <String, Object?>{'month': DateTime.now().month}),
      headerIcon: CupertinoIcons.money_dollar_circle_fill,
      headerTrailing: Semantics(
        button: true,
        label: hidden ? t('home.showMoney') : t('home.hideMoney'),
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 28),
          onPressed: onToggle,
          child: Icon(hidden ? CupertinoIcons.eye_slash_fill : CupertinoIcons.eye_fill, size: 19, color: AppColors.navy),
        ),
      ),
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(t('home.revenueConfirmed'), style: TextStyle(fontSize: 14, color: IosColors.secondaryLabel)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(money(finance.revenueThisMonth), style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: AppColors.text)),
              ),
            ],
          ),
        ),
        IosRow(title: t('home.awaitingFinalizationMoney'), value: money(finance.awaitingFinalizationAmount), chevron: false),
        IosRow(title: t('home.awaitingInvoiceMoney'), value: money(finance.awaitingInvoiceAmount), chevron: false),
        IosRow(title: t('home.maintenanceCost'), value: money(finance.maintenanceCostThisMonth), chevron: false),
        IosRow(title: t('home.revenueYear'), onTap: () => context.push('/dashboard/revenue')),
      ],
    );
  }
}

/// Khung chờ dữ liệu, đứng yên để không tốn khung hình
class _SkeletonGroup extends StatelessWidget {
  final int rows;

  const _SkeletonGroup({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (int index = 0; index < rows; index++)
              Padding(
                padding: EdgeInsets.only(top: index == 0 ? 0 : 14),
                child: FractionallySizedBox(
                  widthFactor: index == rows - 1 ? 0.55 : 0.85,
                  child: Container(height: 14, decoration: BoxDecoration(color: IosColors.fill, borderRadius: BorderRadius.circular(7))),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
