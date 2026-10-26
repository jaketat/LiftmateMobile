// K2: chi tiết một chuyến trong kế hoạch (theo màn N3-ChiTietChuyenKH trên canvas)
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/labels.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../auth/session_provider.dart';
import '../fleet/fleet_api.dart';
import '../plan_3d/plan_3d_api.dart';
import 'plan_vehicle_picker.dart';
import 'planning_api.dart';
import 'planning_providers.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã đổi xe và xếp lại hàng.')));
      }
    } catch (error) {
      if (mounted) {
        showErrorSnackBar(context, error);
      }
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

    // Tiêu đề và nhãn đạt/không đạt chỉ có khi đã tải xong
    String title = 'Chi tiết chuyến';
    final List<Widget> actions = <Widget>[];
    final PlanTripView? view = viewValue.value;
    if (view != null) {
      title = 'Chuyến ${view.trip.sequence}';
      actions.add(Padding(padding: const EdgeInsets.only(right: 12), child: Center(child: _VerdictChip(trip: view.trip))));
    }

    return Scaffold(
      appBar: AppBar(title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)), actions: actions),
      body: AsyncView<PlanTripView>(
        value: viewValue,
        onRetry: () {
          ref.invalidate(planTripProvider(widget.tripKey));
        },
        builder: (PlanTripView view) {
          // Chỉ đổi xe được khi kế hoạch còn là bản Nháp
          final bool showChange = canChange && view.plan.isDraft;
          return RefreshIndicator(
            onRefresh: () {
              return ref.refresh(planTripProvider(widget.tripKey).future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _VehicleCard(trip: view.trip, showChange: showChange, busy: _busy, onChange: _changeVehicle),
                if (view.trip.warnings.isNotEmpty || view.trip.fixHints.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _WarningCard(trip: view.trip),
                ],
                const SizedBox(height: 12),
                _ItemsCard(trip: view.trip),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.view_in_ar_outlined),
                        label: const Text('Xem 3D'),
                        style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
                        onPressed: () {
                          context.push(
                            '/orders/${widget.tripKey.orderId}/plans/${widget.tripKey.planId}/trips/${widget.tripKey.tripId}/3d',
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          foregroundColor: AppColors.navy,
                          side: const BorderSide(color: AppColors.inputBorder),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        onPressed: () {
                          context.push(
                            '/orders/${widget.tripKey.orderId}/plans/${widget.tripKey.planId}/trips/${widget.tripKey.tripId}/2d',
                          );
                        },
                        child: const Text('Sơ đồ 2D'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// Nhãn Đạt / Đạt · sát giới hạn / Không đạt trên thanh tiêu đề
class _VerdictChip extends StatelessWidget {
  final PlanTrip trip;

  const _VerdictChip({required this.trip});

  @override
  Widget build(BuildContext context) {
    String text = label(verdictLabels, trip.verdict);
    Color background = AppColors.okBackground;
    Color foreground = AppColors.okText;
    if (trip.verdict == 'Fail') {
      background = AppColors.errorBackground;
      foreground = AppColors.errorText;
    } else if (trip.verdict == 'Unchecked') {
      background = const Color(0xFFF2F4F7);
      foreground = AppColors.textMuted;
    } else if (trip.nearLimit) {
      text = '$text · sát giới hạn';
      background = AppColors.warnBackground;
      foreground = AppColors.warnText;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: foreground)),
    );
  }
}

BoxDecoration _cardDecoration({Color borderColor = AppColors.border}) {
  return BoxDecoration(
    color: Colors.white,
    border: Border.all(color: borderColor),
    borderRadius: BorderRadius.circular(14),
  );
}

// Xe của chuyến, hàng trên xe, nút "Đổi xe"
class _VehicleCard extends StatelessWidget {
  final PlanTrip trip;
  final bool showChange;
  final bool busy;
  final VoidCallback onChange;

  const _VehicleCard({required this.trip, required this.showChange, required this.busy, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final PlanVehicle? carrier = trip.carrier;
    String vehicleText = 'Chưa chọn xe';
    num payload = 0;
    if (carrier != null) {
      vehicleText = '${label(vehicleBaseTypeLabels, carrier.baseType)} ${carrier.plateNumber}';
      payload = carrier.payloadKg;
      final PlanVehicle? tractor = trip.tractor;
      if (tractor != null) {
        vehicleText = '$vehicleText + đầu kéo ${tractor.plateNumber}';
      }
    }

    // Thanh tải: đầy quá thì chuyển đỏ
    double ratio = 0;
    if (payload > 0) {
      ratio = (trip.cargoKg / payload).toDouble();
    }
    final Color barColor = ratio > 1 ? AppColors.errorText : AppColors.navy;

    String weightText = formatKg(trip.cargoKg);
    if (payload > 0) {
      weightText = '${formatNumber(trip.cargoKg)} / ${formatKg(payload)}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(vehicleText, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
              if (showChange)
                TextButton(
                  onPressed: busy ? null : onChange,
                  child: busy
                      ? const SizedBox(width: 16, height: 16, child: CupertinoActivityIndicator())
                      : const Text('Đổi xe'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Hàng trên xe', style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
              Text(weightText, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: const Color(0xFFF2F4F7),
              color: barColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Xe do máy đề xuất khi chia chuyến. Đợt giao ${trip.deliveryWave}.',
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

// Vì sao không đạt (hoặc lưu ý) và gợi ý sửa: hiện thẳng chữ server trả
class _WarningCard extends StatelessWidget {
  final PlanTrip trip;

  const _WarningCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    final bool failed = trip.verdict == 'Fail';
    final Color titleColor = failed ? AppColors.errorText : AppColors.warnText;

    final List<Widget> children = <Widget>[
      Text(
        failed ? 'Vì sao không đạt' : 'Lưu ý',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: titleColor),
      ),
    ];
    for (final String warning in trip.warnings) {
      children.add(const SizedBox(height: 6));
      children.add(Text(warning, style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.label)));
    }
    if (trip.fixHints.isNotEmpty) {
      children.add(const SizedBox(height: 10));
      children.add(const Text('Gợi ý sửa', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.label)));
      for (final String hint in trip.fixHints) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  ', style: TextStyle(fontSize: 14)),
                Expanded(child: Text(hint, style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.label))),
              ],
            ),
          ),
        );
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: _cardDecoration(borderColor: failed ? const Color(0xFFF3B8B2) : AppColors.border),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

// Kiện trên chuyến: tên × số lượng
class _ItemsCard extends StatelessWidget {
  final PlanTrip trip;

  const _ItemsCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          const Text('Kiện trên chuyến', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          Text('${trip.itemCount} kiện', style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
        ],
      ),
    ];
    if (trip.items.isEmpty) {
      children.add(const SizedBox(height: 8));
      children.add(const Text('Chuyến này chưa có kiện.', style: TextStyle(color: AppColors.textMuted)));
    }
    for (int i = 0; i < trip.items.length; i++) {
      final PlanItem item = trip.items[i];
      children.add(const SizedBox(height: 8));
      if (i > 0) {
        children.add(const Divider(height: 1, color: Color(0xFFF2F4F7)));
        children.add(const SizedBox(height: 8));
      }
      children.add(
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(item.cargoName, style: const TextStyle(fontSize: 14))),
            Text('× ${item.quantity}', style: const TextStyle(fontSize: 14, color: AppColors.textMuted)),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: _cardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}
