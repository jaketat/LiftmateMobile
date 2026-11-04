// K2: chi tiết một chuyến trong kế hoạch (theo màn N3-ChiTietChuyenKH trên canvas)
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../auth/session_provider.dart';
import '../fleet/fleet_api.dart';
import '../plan_3d/plan_3d_api.dart';
import 'packing_summary.dart';
import 'plan_vehicle_picker.dart';
import 'planning_api.dart';
import 'planning_providers.dart';
import '../../core/widgets/ios.dart';

class PlanTripScreen extends ConsumerStatefulWidget {
  final TripKey tripKey;

  const PlanTripScreen({super.key, required this.tripKey});

  @override
  ConsumerState<PlanTripScreen> createState() => _PlanTripScreenState();
}

class _PlanTripScreenState extends ConsumerState<PlanTripScreen> {
  // true: đang đổi xe, khóa nút
  bool _busy = false;

  // Chọn xe mới (moóc thì chọn thêm đầu kéo), gọi API, rồi tải lại kế hoạch
  Future<void> _changeVehicle() async {
    final Vehicle? carrier = await pickVehicle(context, tractors: false);
    if (carrier == null || !mounted) {
      return;
    }
    Vehicle? tractor;
    if (carrier.baseType == 'Trailer') {
      tractor = await pickVehicle(context, tractors: true);
      // Moóc mà không chọn đầu kéo thì thôi, không gửi
      if (tractor == null || !mounted) {
        return;
      }
    }

    setState(() {
      _busy = true;
    });
    try {
      await changeTripVehicle(
        (orderId: widget.tripKey.orderId, planId: widget.tripKey.planId),
        widget.tripKey.tripId,
        carrier.publicId,
        tractor?.publicId,
      );
      if (mounted) {
        showIosToast(context, t('planning.trip.changed'));
      }
    } catch (error) {
      if (mounted) showIosToast(context, errorMessage(error), isError: true);
    }
    // Dù thành công hay lỗi đều tải lại từ server
    ref.invalidate(planTripProvider(widget.tripKey));
    ref.invalidate(currentPlanProvider(widget.tripKey.orderId));
    if (mounted) {
      setState(() {
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<PlanTripView> viewValue = ref.watch(planTripProvider(widget.tripKey));
    final Session? session = ref.watch(sessionProvider).value;
    final bool canChange = session != null && session.can('Packing.Run3D');
    final PlanTripView? view = viewValue.hasError ? null : viewValue.value;
    final String base = '/orders/${widget.tripKey.orderId}/plans/${widget.tripKey.planId}/trips/${widget.tripKey.tripId}';

    return IosPage(
      title: view == null ? t('planning.trip.title') : t('planning.tripNumber', <String, Object?>{'sequence': view.trip.sequence}),
      onRefresh: () => ref.refresh(planTripProvider(widget.tripKey).future).then((_) {}, onError: (Object _) {}),
      slivers: view == null
          ? <Widget>[
              SliverFillRemaining(
                hasScrollBody: false,
                child: AsyncView<PlanTripView>(
                  value: viewValue,
                  onRetry: () => ref.invalidate(planTripProvider(widget.tripKey)),
                  builder: (PlanTripView _) => const SizedBox.shrink(),
                ),
              ),
            ]
          : <Widget>[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: Align(alignment: Alignment.centerLeft, child: PlanVerdictPill(trip: view.trip)),
                ),
              ),
              // Chỉ đổi xe được khi kế hoạch còn là bản Nháp
              SliverToBoxAdapter(child: _VehicleGroup(trip: view.trip, showChange: canChange && view.plan.isDraft, busy: _busy, onChange: _changeVehicle)),
              SliverToBoxAdapter(
                child: IosGroup(
                  header: t('planning.trip.viewHeader'),
                  headerIcon: CupertinoIcons.view_3d,
                  dividerIndent: 62,
                  children: <Widget>[
                    IosRow(icon: CupertinoIcons.cube_fill, iconColor: AppColors.orange, title: t('planning.trip.view3d'), onTap: () => context.push('$base/3d')),
                    IosRow(icon: CupertinoIcons.square_grid_2x2_fill, iconColor: IosColors.blue, title: t('planning.trip.diagram2d'), onTap: () => context.push('$base/2d')),
                  ],
                ),
              ),
              if (view.trip.warnings.isNotEmpty || view.trip.fixHints.isNotEmpty) SliverToBoxAdapter(child: _WarningGroup(trip: view.trip)),
              SliverToBoxAdapter(child: _ItemsGroup(trip: view.trip)),
            ],
    );
  }
}

// Xe của chuyến, hàng trên xe so với tải trọng, nút "Đổi xe"
class _VehicleGroup extends StatelessWidget {
  final PlanTrip trip;
  final bool showChange;
  final bool busy;
  final VoidCallback onChange;

  const _VehicleGroup({required this.trip, required this.showChange, required this.busy, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final num payload = trip.carrier?.payloadKg ?? 0;
    final double ratio = payload > 0 ? (trip.cargoKg / payload).toDouble() : 0;
    final String weightText = payload > 0 ? '${formatNumber(trip.cargoKg)} / ${formatKg(payload)}' : formatKg(trip.cargoKg);
    return IosGroup(
      header: t('planning.trip.vehicleHeader'),
      headerIcon: CupertinoIcons.car_detailed,
      footer: t('planning.trip.vehicleNote', <String, Object?>{'wave': trip.deliveryWave}),
      children: <Widget>[
        IosRow(
          title: planVehicleText(trip),
          chevron: false,
          trailing: showChange
              ? CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 32),
                  onPressed: busy ? null : onChange,
                  child: busy
                      ? const CupertinoActivityIndicator()
                      : Text(t('planning.trip.changeVehicle'), style: TextStyle(fontSize: 17, color: IosColors.blue)),
                )
              : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: Text(t('planning.trip.cargoOnVehicle'), style: TextStyle(fontSize: 17, color: AppColors.text))),
                  Text(weightText, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text)),
                ],
              ),
              // Thanh tải: đầy quá thì chuyển đỏ, sát đầy thì cam
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio.clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: AppColors.fillSoft,
                  color: ratio > 1 ? IosColors.red : (ratio > 0.9 ? IosColors.orange : IosColors.green),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Vì sao không đạt (hoặc lưu ý) và gợi ý sửa: hiện thẳng chữ server trả
class _WarningGroup extends StatelessWidget {
  final PlanTrip trip;

  const _WarningGroup({required this.trip});

  @override
  Widget build(BuildContext context) {
    final bool failed = trip.verdict == 'Fail';
    return IosGroup(
      header: failed ? t('planning.trip.whyFailed') : t('planning.trip.notice'),
      headerIcon: CupertinoIcons.exclamationmark_triangle_fill,
      dividerIndent: 62,
      children: <Widget>[
        for (final String warning in trip.warnings)
          IosRow(
            icon: failed ? CupertinoIcons.xmark_octagon_fill : CupertinoIcons.exclamationmark_circle_fill,
            iconColor: failed ? IosColors.red : IosColors.orange,
            title: warning,
            chevron: false,
          ),
        for (final String hint in trip.fixHints)
          IosRow(icon: CupertinoIcons.lightbulb_fill, iconColor: IosColors.blue, title: hint, subtitle: t('planning.trip.fixHints'), chevron: false),
      ],
    );
  }
}

// Kiện trên chuyến: tên × số lượng
class _ItemsGroup extends StatelessWidget {
  final PlanTrip trip;

  const _ItemsGroup({required this.trip});

  @override
  Widget build(BuildContext context) {
    return IosGroup(
      header: '${t('planning.trip.items')} · ${t('planning.trip.itemCount', <String, Object?>{'count': trip.itemCount})}',
      headerIcon: CupertinoIcons.cube_box_fill,
      children: <Widget>[
        if (trip.items.isEmpty) IosRow(title: t('planning.trip.noItems'), chevron: false),
        for (final PlanItem item in trip.items) IosRow(title: item.cargoName, value: '× ${item.quantity}', chevron: false),
      ],
    );
  }
}
