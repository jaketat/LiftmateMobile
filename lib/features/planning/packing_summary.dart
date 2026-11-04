// Xếp hàng 3D trong đơn hàng: thẻ tóm tắt kế hoạch xếp (số chuyến, xe, đạt/không đạt), bấm chuyến mở thẳng màn 3D.
// Dùng ở chi tiết đơn; màn kế hoạch dùng lại các dòng chuyến và nhãn đạt/không đạt ở đây.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/call.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/labels.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ios.dart';
import '../auth/session_provider.dart';
import 'planning_api.dart';
import 'planning_providers.dart';

/// Xe của chuyến: "Xe tải 51C-900.01" hoặc "Sơ mi rơ moóc 51R-900.03 + đầu kéo 51D-900.02"
String planVehicleText(PlanTrip trip) {
  final PlanVehicle? carrier = trip.carrier;
  if (carrier == null) return t('planning.noVehicle');
  final String text = '${label(vehicleBaseTypeLabels, carrier.baseType)} ${carrier.plateNumber}';
  final PlanVehicle? tractor = trip.tractor;
  return tractor == null ? text : t('planning.withTractor', <String, Object?>{'vehicle': text, 'plate': tractor.plateNumber});
}

/// "8 kiện · 13.900 / 15.000 kg"
String planTripLoadText(PlanTrip trip) {
  final PlanVehicle? carrier = trip.carrier;
  final String weight = carrier != null && carrier.payloadKg > 0
      ? '${formatNumber(trip.cargoKg)} / ${formatKg(carrier.payloadKg)}'
      : formatKg(trip.cargoKg);
  return '${t('planning.trip.itemCount', <String, Object?>{'count': trip.itemCount})} · $weight';
}

/// Nhãn Đạt / Đạt · sát giới hạn / Không đạt / Chưa kiểm
class PlanVerdictPill extends StatelessWidget {
  final PlanTrip trip;

  const PlanVerdictPill({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    final String text = label(verdictLabels, trip.verdict);
    if (trip.verdict == 'Fail') return IosPill(text, color: IosColors.red);
    if (trip.verdict == 'Unchecked') return IosPill(text, color: IosColors.secondaryLabel);
    if (trip.nearLimit) return IosPill(t('planning.nearLimit', <String, Object?>{'verdict': text}), color: IosColors.orange);
    return IosPill(text, color: IosColors.green);
  }
}

/// Một chuyến: biển số, loại xe, hàng trên xe, nhãn kiểm tra
class PlanTripRow extends StatelessWidget {
  final PlanTrip trip;
  final VoidCallback onTap;

  const PlanTripRow({super.key, required this.trip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Ngắn gọn để nhãn bên phải không bị ép: biển số ở tiêu đề, loại xe và tải ở dòng phụ; cảnh báo xem ở chi tiết chuyến
    final PlanVehicle? carrier = trip.carrier;
    final String plate = carrier == null
        ? t('planning.noVehicle')
        : trip.tractor == null
            ? carrier.plateNumber
            : '${carrier.plateNumber} + ${trip.tractor!.plateNumber}';
    final String type = carrier == null ? '' : '${label(vehicleBaseTypeLabels, carrier.baseType)} · ';
    return IosRow(
      icon: CupertinoIcons.cube_box_fill,
      iconColor: trip.verdict == 'Fail' ? IosColors.red : AppColors.orange,
      title: '${t('planning.tripNumber', <String, Object?>{'sequence': trip.sequence})} · $plate',
      subtitle: '$type${planTripLoadText(trip)}',
      trailing: PlanVerdictPill(trip: trip),
      onTap: onTap,
    );
  }
}

String planTripPath(String orderId, String planId, String tripId) => '/orders/$orderId/plans/$planId/trips/$tripId';

/// Thẻ "Xếp hàng lên xe" trong chi tiết đơn. Chưa có kế hoạch thì có nút xếp hàng ngay (cần quyền chạy 3D);
/// có rồi thì hiện từng chuyến, bấm vào xem 3D luôn, dòng cuối mở màn kế hoạch đầy đủ (duyệt, đổi xe, tiền dầu).
class PackingGroup extends ConsumerStatefulWidget {
  final String orderId;

  const PackingGroup({super.key, required this.orderId});

  @override
  ConsumerState<PackingGroup> createState() => _PackingGroupState();
}

class _PackingGroupState extends ConsumerState<PackingGroup> {
  bool generating = false;

  Future<void> generate() async {
    setState(() => generating = true);
    try {
      await generatePlan(widget.orderId);
    } catch (error) {
      if (mounted) showIosToast(context, errorMessage(error), isError: true);
    }
    ref.invalidate(currentPlanProvider(widget.orderId));
    if (mounted) setState(() => generating = false);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<ShipmentPlan> value = ref.watch(currentPlanProvider(widget.orderId));
    final Session? session = ref.watch(sessionProvider).value;
    final bool canRun = session?.can('Packing.Run3D') ?? false;
    final Object? error = value.error;
    final bool noPlan = value.hasError && error is ApiException && error.code == 'PLAN_NOT_FOUND';
    final ShipmentPlan? plan = value.hasError ? null : value.value;
    final String plansPath = '/orders/${widget.orderId}/plan';

    Widget? footer;
    final List<Widget> rows = <Widget>[];
    if (generating || (value.isLoading && plan == null && !noPlan)) {
      rows.add(Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 8,
          children: <Widget>[
            const CupertinoActivityIndicator(),
            if (generating) Text(t('packing.generating'), style: TextStyle(fontSize: 15, color: IosColors.secondaryLabel)),
          ],
        ),
      ));
    } else if (noPlan) {
      rows.add(IosRow(
        icon: CupertinoIcons.cube_box,
        iconColor: AppColors.orange,
        title: t('packing.none'),
        subtitle: canRun ? t('packing.noneHint') : t('planning.plan.noPermission'),
        chevron: false,
      ));
      if (canRun) {
        rows.add(IosRow(
          icon: CupertinoIcons.sparkles,
          iconColor: IosColors.blue,
          title: t('packing.generate'),
          onTap: generate,
        ));
      }
    } else if (plan == null) {
      rows.add(IosRow(
        icon: CupertinoIcons.exclamationmark_circle,
        iconColor: IosColors.red,
        title: errorMessage(error ?? ''),
        subtitle: t('common.retry'),
        onTap: () => ref.invalidate(currentPlanProvider(widget.orderId)),
      ));
    } else {
      rows.add(IosRow(
        icon: CupertinoIcons.chart_bar_square_fill,
        iconColor: AppColors.navy,
        title: t('packing.summary', <String, Object?>{
          'trips': plan.trips.length,
          'kg': formatKg(plan.totalKg),
          'items': plan.totalItems,
        }),
        trailing: IosPill(label(planStatusLabels, plan.status), color: plan.isDraft ? IosColors.orange : IosColors.green),
        chevron: false,
      ));
      for (final PlanTrip trip in plan.trips) {
        rows.add(PlanTripRow(
          trip: trip,
          // Bấm chuyến là xem 3D luôn: việc hay làm nhất khi mở đơn
          onTap: () => context.push('${planTripPath(widget.orderId, plan.id, trip.id)}/3d'),
        ));
      }
      rows.add(IosRow(icon: CupertinoIcons.square_stack_3d_up_fill, iconColor: IosColors.blue, title: t('packing.openPlan'), onTap: () => context.push(plansPath)));
      final int unplanned = plan.unplanned.fold<int>(0, (int sum, UnplannedCargo c) => sum + c.quantity);
      final String? note = plan.isStale
          ? t('packing.stale')
          : unplanned > 0
              ? t('planning.plan.unplanned', <String, Object?>{'count': unplanned})
              : null;
      if (note != null) footer = Text(note, style: TextStyle(fontSize: 13, height: 1.35, color: AppColors.warnText));
    }

    return IosGroup(
      header: t('packing.header'),
      headerIcon: CupertinoIcons.cube_box_fill,
      dividerIndent: 62,
      footerWidget: footer,
      children: rows,
    );
  }
}
