// K1: kế hoạch chia chuyến của một đơn (theo màn N3-KeHoach trên canvas), giao diện kiểu iOS như các màn đơn hàng
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push
import 'package:go_router/go_router.dart';

import '../../core/api/call.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/labels.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/ios.dart';
import '../auth/session_provider.dart';
import 'packing_summary.dart';
import 'planning_api.dart';
import 'planning_providers.dart';

class PlanScreen extends ConsumerStatefulWidget {
  final String orderId;

  const PlanScreen({super.key, required this.orderId});

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  // 'generate' | 'approve': đang chạy việc nào, khóa nút để khỏi bấm hai lần
  String? _busy;

  // Chia chuyến hoặc lên lại kế hoạch: cùng một API, mỗi lần tạo bản Nháp mới
  Future<void> _generate() async {
    setState(() => _busy = 'generate');
    try {
      await generatePlan(widget.orderId);
    } catch (error) {
      if (mounted) showIosToast(context, errorMessage(error), isError: true);
    }
    // Dù thành công hay lỗi đều tải lại từ server, không tự sửa danh sách trong máy
    ref.invalidate(currentPlanProvider(widget.orderId));
    if (mounted) setState(() => _busy = null);
  }

  Future<void> _approve(ShipmentPlan plan) async {
    setState(() => _busy = 'approve');
    try {
      await approvePlan((orderId: widget.orderId, planId: plan.id));
    } catch (error) {
      if (mounted) showIosToast(context, errorMessage(error), isError: true);
    }
    ref.invalidate(currentPlanProvider(widget.orderId));
    if (mounted) setState(() => _busy = null);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<ShipmentPlan> planValue = ref.watch(currentPlanProvider(widget.orderId));
    final Session? session = ref.watch(sessionProvider).value;
    final bool canRun = session != null && session.can('Packing.Run3D');
    final bool canApprove = session != null && session.can('Packing.Approve');

    // Đơn chưa chia chuyến: server trả 404 PLAN_NOT_FOUND, màn chỉ có nút "Chia chuyến"
    final Object? error = planValue.error;
    final bool noPlanYet = planValue.hasError && error is ApiException && error.code == 'PLAN_NOT_FOUND';
    final ShipmentPlan? plan = planValue.hasError ? null : planValue.value;

    final List<Widget> slivers;
    if (noPlanYet) {
      slivers = <Widget>[SliverToBoxAdapter(child: _NoPlanGroup(canRun: canRun))];
    } else if (plan == null) {
      slivers = <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: AsyncView<ShipmentPlan>(
            value: planValue,
            onRetry: () => ref.invalidate(currentPlanProvider(widget.orderId)),
            builder: (ShipmentPlan _) => const SizedBox.shrink(),
          ),
        ),
      ];
    } else {
      slivers = _planSlivers(plan);
    }

    return IosPage(
      title: t('planning.plan.title'),
      onRefresh: () => ref.refresh(currentPlanProvider(widget.orderId).future).then((_) {}, onError: (Object _) {}),
      bottom: noPlanYet
          ? (canRun ? _ActionBar(primary: t('planning.plan.generate'), busy: _busy == 'generate', onPrimary: _busy == null ? _generate : null) : null)
          : plan == null
              ? null
              : _planBar(plan, canRun: canRun, canApprove: canApprove),
      slivers: slivers,
    );
  }

  // Lý do chưa duyệt được (null: duyệt được)
  String? _blockReason(ShipmentPlan plan) {
    if (!plan.isDraft) return null;
    if (plan.isStale) return t('planning.plan.blockStale');
    final List<PlanTrip> failed = plan.failedTrips;
    if (failed.isEmpty) return null;
    return t('planning.plan.blockFailed', <String, Object?>{'numbers': failed.map((PlanTrip trip) => '${trip.sequence}').join(', ')});
  }

  Widget? _planBar(ShipmentPlan plan, {required bool canRun, required bool canApprove}) {
    final bool approvable = plan.isDraft && canApprove;
    if (!canRun && !approvable) return null;
    final bool blocked = _blockReason(plan) != null;
    return _ActionBar(
      secondary: canRun ? t('planning.plan.regenerate') : null,
      secondaryBusy: _busy == 'generate',
      onSecondary: _busy == null ? _generate : null,
      primary: approvable ? t('planning.plan.approve') : null,
      busy: _busy == 'approve',
      onPrimary: _busy == null && !blocked ? () => _approve(plan) : null,
    );
  }

  List<Widget> _planSlivers(ShipmentPlan plan) {
    final int unplanned = plan.unplanned.fold<int>(0, (int sum, UnplannedCargo c) => sum + c.quantity);
    final int pending = plan.pending.fold<int>(0, (int sum, PendingCargo c) => sum + c.quantity);
    final List<String> pendingDates = <String>[
      for (final PendingCargo cargo in plan.pending)
        if (cargo.readyDate != null) formatDate(cargo.readyDate),
    ].toSet().toList();
    final String? blockReason = _blockReason(plan);
    final TextStyle note = TextStyle(fontSize: 13, height: 1.35, color: IosColors.secondaryLabel);

    return <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Row(
            spacing: 8,
            children: <Widget>[
              IosPill(label(planStatusLabels, plan.status), color: plan.isDraft ? IosColors.orange : IosColors.green),
              Text(t('planning.plan.versionShort', <String, Object?>{'version': plan.version}), style: note),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(child: _SummaryGroup(orderId: widget.orderId, plan: plan)),
      if (plan.isStale || unplanned > 0 || pending > 0)
        SliverToBoxAdapter(
          child: IosGroup(
            header: t('planning.plan.attention'),
            headerIcon: CupertinoIcons.exclamationmark_triangle_fill,
            children: <Widget>[
              if (plan.isStale)
                IosRow(
                  icon: CupertinoIcons.arrow_2_circlepath,
                  iconColor: IosColors.orange,
                  title: t('planning.plan.staleTitle'),
                  subtitle: t('planning.plan.staleText'),
                  chevron: false,
                ),
              if (unplanned > 0)
                IosRow(
                  icon: CupertinoIcons.xmark_octagon_fill,
                  iconColor: IosColors.red,
                  title: t('planning.plan.unplanned', <String, Object?>{'count': unplanned}),
                  subtitle: plan.unplanned.map((UnplannedCargo c) => c.message).where((String m) => m.isNotEmpty).join('\n'),
                  chevron: false,
                ),
              if (pending > 0)
                IosRow(
                  icon: CupertinoIcons.clock_fill,
                  iconColor: IosColors.orange,
                  title: t('planning.plan.pending', <String, Object?>{'count': pending}),
                  subtitle: pendingDates.isEmpty
                      ? t('planning.plan.pendingDefault')
                      : t('planning.plan.pendingDates', <String, Object?>{'dates': pendingDates.join(', ')}),
                  chevron: false,
                ),
            ],
          ),
        ),
      SliverToBoxAdapter(
        child: IosGroup(
          header: t('planning.plan.tripsHeader', <String, Object?>{'count': plan.trips.length}),
          headerIcon: CupertinoIcons.cube_box_fill,
          dividerIndent: 62,
          footerWidget: blockReason != null && plan.isDraft
              ? Text(blockReason, style: note.copyWith(color: IosColors.red))
              : !plan.isDraft
                  ? Text(t('planning.plan.statusNote', <String, Object?>{'status': label(planStatusLabels, plan.status).toLowerCase()}), style: note)
                  : Text(t('planning.plan.tripsHint'), style: note),
          children: <Widget>[
            if (plan.trips.isEmpty)
              IosRow(title: t('planning.plan.noTrips'), chevron: false),
            for (final PlanTrip trip in plan.trips)
              PlanTripRow(trip: trip, onTap: () => context.push(planTripPath(widget.orderId, plan.id, trip.id))),
          ],
        ),
      ),
    ];
  }
}

/// Số chuyến, tổng hàng, tiền dầu khứ hồi (bấm mở chi tiết tiền dầu)
class _SummaryGroup extends ConsumerWidget {
  final String orderId;
  final ShipmentPlan plan;

  const _SummaryGroup({required this.orderId, required this.plan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final num? cost = ref.watch(costTotalProvider((orderId: orderId, planId: plan.id))).value;
    return IosGroup(
      header: t('planning.plan.summaryHeader'),
      headerIcon: CupertinoIcons.chart_bar_square_fill,
      children: <Widget>[
        IosRow(
          title: t('planning.plan.tripCount'),
          subtitle: plan.lowerBoundTrips > 0 ? t('planning.plan.atLeast', <String, Object?>{'count': plan.lowerBoundTrips}) : null,
          value: '${plan.trips.length}',
          chevron: false,
        ),
        IosRow(
          title: t('tripDetail.info.cargo'),
          value: '${formatKg(plan.totalKg)} · ${t('planning.trip.itemCount', <String, Object?>{'count': plan.totalItems})}',
          chevron: false,
        ),
        IosRow(
          title: t('planning.cost.fuelRound'),
          // Chưa tải xong hoặc lỗi thì hiện "—", không chặn màn
          value: cost == null ? '—' : formatMoney(cost),
          onTap: () => context.push('/orders/$orderId/plans/${plan.id}/cost'),
        ),
      ],
    );
  }
}

/// Đơn chưa có kế hoạch
class _NoPlanGroup extends StatelessWidget {
  final bool canRun;

  const _NoPlanGroup({required this.canRun});

  @override
  Widget build(BuildContext context) {
    return IosGroup(
      footer: canRun ? t('planning.plan.noPlanHint') : t('planning.plan.noPermission'),
      children: <Widget>[
        IosRow(icon: CupertinoIcons.cube_box, iconColor: AppColors.orange, title: t('planning.plan.noPlan'), chevron: false),
      ],
    );
  }
}

/// Thanh nút kính nổi ở đáy, như thanh lưu ở màn tạo đơn: nút phụ (Lên lại kế hoạch) và nút chính (Duyệt / Chia chuyến)
class _ActionBar extends StatelessWidget {
  final String? primary;
  final bool busy;
  final VoidCallback? onPrimary;
  final String? secondary;
  final bool secondaryBusy;
  final VoidCallback? onSecondary;

  const _ActionBar({this.primary, this.busy = false, this.onPrimary, this.secondary, this.secondaryBusy = false, this.onSecondary});

  @override
  Widget build(BuildContext context) {
    final Widget? secondaryButton = secondary == null
        ? null
        : CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onSecondary,
            child: Container(
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.fillSoft, borderRadius: BorderRadius.circular(999)),
              child: secondaryBusy
                  ? const CupertinoActivityIndicator()
                  : Text(secondary!, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: IosColors.blue)),
            ),
          );
    final Widget? primaryButton = primary == null
        ? null
        : SizedBox(height: 50, child: IosPillButton(label: primary!, busy: busy, onPressed: onPrimary));
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.paddingOf(context).bottom + 10),
      child: Glass(
        borderRadius: BorderRadius.circular(32),
        opacity: 0.85,
        padding: const EdgeInsets.all(8),
        child: Row(
          spacing: 8,
          children: <Widget>[
            if (secondaryButton != null) Expanded(child: secondaryButton),
            if (primaryButton != null) Expanded(flex: secondaryButton == null ? 1 : 2, child: primaryButton),
          ],
        ),
      ),
    );
  }
}
