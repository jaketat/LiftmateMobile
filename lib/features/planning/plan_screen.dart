// K1: kế hoạch chia chuyến của một đơn (theo màn N3-KeHoach trên canvas)
import 'package:flutter/material.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push
import 'package:go_router/go_router.dart';

import '../../core/api/call.dart';
import '../../core/format.dart';
import '../../core/labels.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../auth/session_provider.dart';
import 'planning_api.dart';
import 'planning_providers.dart';

class PlanScreen extends ConsumerStatefulWidget {
  final String orderId;

  const PlanScreen({super.key, required this.orderId});

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  // true: đang chia chuyến hoặc đang duyệt, khóa nút để khỏi bấm hai lần
  bool _busy = false;
  // Chữ hiện trên nút đang chạy, vd "Đang chia chuyến..."
  String _busyText = '';

  // Chia chuyến hoặc lên lại kế hoạch: cùng một API, mỗi lần tạo bản Nháp mới
  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _busyText = 'Đang chia chuyến...';
    });
    try {
      await generatePlan(widget.orderId);
    } catch (error) {
      if (mounted) {
        showErrorSnackBar(context, error);
      }
    }
    // Dù thành công hay lỗi đều tải lại từ server, không tự sửa danh sách trong máy
    ref.invalidate(currentPlanProvider(widget.orderId));
    if (mounted) {
      setState(() {
        _busy = false;
      });
    }
  }

  Future<void> _approve(ShipmentPlan plan) async {
    setState(() {
      _busy = true;
      _busyText = 'Đang duyệt...';
    });
    try {
      await approvePlan((orderId: widget.orderId, planId: plan.id));
    } catch (error) {
      if (mounted) {
        showErrorSnackBar(context, error);
      }
    }
    ref.invalidate(currentPlanProvider(widget.orderId));
    if (mounted) {
      setState(() {
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<ShipmentPlan> planValue = ref.watch(currentPlanProvider(widget.orderId));
    final Session? session = ref.watch(sessionProvider).value;
    final bool canRun = session != null && session.can('Packing.Run3D');
    final bool canApprove = session != null && session.can('Packing.Approve');

    // Dòng phụ: "phiên bản 2 · Nháp"
    String subtitle = '';
    final ShipmentPlan? plan = planValue.value;
    if (plan != null) {
      subtitle = 'phiên bản ${plan.version} · ${label(planStatusLabels, plan.status)}';
    }

    // Đơn chưa chia chuyến: server trả 404 PLAN_NOT_FOUND, màn chỉ có nút "Chia chuyến"
    final Object? error = planValue.error;
    final bool noPlanYet = planValue.hasError && error is ApiException && error.code == 'PLAN_NOT_FOUND';

    Widget body;
    if (noPlanYet) {
      body = _NoPlanView(
        canRun: canRun,
        busy: _busy,
        busyText: _busyText,
        onGenerate: _generate,
      );
    } else {
      body = AsyncView<ShipmentPlan>(
        value: planValue,
        onRetry: () {
          ref.invalidate(currentPlanProvider(widget.orderId));
        },
        builder: (ShipmentPlan plan) {
          return _PlanBody(
            orderId: widget.orderId,
            plan: plan,
            canRun: canRun,
            canApprove: canApprove,
            busy: _busy,
            busyText: _busyText,
            onGenerate: _generate,
            onApprove: () {
              _approve(plan);
            },
            onRefresh: () {
              return ref.refresh(currentPlanProvider(widget.orderId).future);
            },
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Kế hoạch chia chuyến', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            if (subtitle.isNotEmpty)
              Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
        ),
      ),
      body: body,
    );
  }
}

// Nút chính: bình thường là chữ, đang chạy thì hiện vòng xoay và chữ "Đang ..."
class _BusyLabel extends StatelessWidget {
  final bool busy;
  final String busyText;
  final String text;

  const _BusyLabel({required this.busy, required this.busyText, required this.text});

  @override
  Widget build(BuildContext context) {
    if (!busy) {
      return Text(text);
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 8),
        Flexible(child: Text(busyText, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

// Đơn chưa có kế hoạch
class _NoPlanView extends StatelessWidget {
  final bool canRun;
  final bool busy;
  final String busyText;
  final VoidCallback onGenerate;

  const _NoPlanView({required this.canRun, required this.busy, required this.busyText, required this.onGenerate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Đơn này chưa được chia chuyến.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Máy sẽ chia kiện thành các chuyến và chọn xe cho từng chuyến.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            // Không có quyền chạy kế hoạch thì ẩn nút (doc mục 2.8)
            if (canRun)
              FilledButton(
                onPressed: busy ? null : onGenerate,
                child: _BusyLabel(busy: busy, busyText: busyText, text: 'Chia chuyến'),
              )
            else
              const Text(
                'Bạn chưa có quyền chia chuyến.',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlanBody extends StatelessWidget {
  final String orderId;
  final ShipmentPlan plan;
  final bool canRun;
  final bool canApprove;
  final bool busy;
  final String busyText;
  final VoidCallback onGenerate;
  final VoidCallback onApprove;
  final Future<ShipmentPlan> Function() onRefresh;

  const _PlanBody({
    required this.orderId,
    required this.plan,
    required this.canRun,
    required this.canApprove,
    required this.busy,
    required this.busyText,
    required this.onGenerate,
    required this.onApprove,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[
      _SummaryPanel(orderId: orderId, plan: plan),
    ];

    // Kế hoạch cũ: băng vàng, khóa nút Duyệt
    if (plan.isStale) {
      children.add(const SizedBox(height: 10));
      children.add(
        const _NoticeBox(
          background: AppColors.warnBackground,
          foreground: AppColors.warnText,
          title: 'Kế hoạch đã cũ.',
          text: ' Kiện, điểm dừng hoặc xe đã đổi sau khi chia chuyến. Hãy lên lại kế hoạch.',
        ),
      );
    }

    // Kiện không xếp được: khung đỏ
    if (plan.unplanned.isNotEmpty) {
      int count = 0;
      final List<String> reasons = <String>[];
      for (final UnplannedCargo cargo in plan.unplanned) {
        count += cargo.quantity;
        if (cargo.message.isNotEmpty) {
          reasons.add(cargo.message);
        }
      }
      children.add(const SizedBox(height: 10));
      children.add(
        _NoticeBox(
          background: AppColors.errorBackground,
          foreground: AppColors.errorText,
          title: '$count kiện không xếp được.',
          text: reasons.isEmpty ? '' : ' ${reasons.join(' ')}',
        ),
      );
    }

    // Kiện chưa sẵn sàng: khung vàng
    if (plan.pending.isNotEmpty) {
      int count = 0;
      final List<String> dates = <String>[];
      for (final PendingCargo cargo in plan.pending) {
        count += cargo.quantity;
        if (cargo.readyDate != null) {
          final String date = formatDate(cargo.readyDate);
          if (!dates.contains(date)) {
            dates.add(date);
          }
        }
      }
      String text = ' Sẽ được chia khi hàng sẵn sàng.';
      if (dates.isNotEmpty) {
        text = ' Ngày sẵn sàng: ${dates.join(', ')}.';
      }
      children.add(const SizedBox(height: 10));
      children.add(
        _NoticeBox(
          background: AppColors.warnBackground,
          foreground: AppColors.warnText,
          title: '$count kiện chưa sẵn sàng.',
          text: text,
        ),
      );
    }

    if (plan.trips.isEmpty) {
      children.add(const SizedBox(height: 24));
      children.add(
        const Center(child: Text('Kế hoạch chưa có chuyến nào.', style: TextStyle(color: AppColors.textMuted))),
      );
    }
    for (final PlanTrip trip in plan.trips) {
      children.add(const SizedBox(height: 10));
      children.add(_TripCard(orderId: orderId, planId: plan.id, trip: trip));
    }

    return Column(
      children: [
        Expanded(
          // Kéo xuống để tải lại
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: children,
            ),
          ),
        ),
        _BottomBar(
          plan: plan,
          canRun: canRun,
          canApprove: canApprove,
          busy: busy,
          busyText: busyText,
          onGenerate: onGenerate,
          onApprove: onApprove,
        ),
      ],
    );
  }
}

// Khung xanh đậm: số chuyến, tổng hàng, dầu khứ hồi
class _SummaryPanel extends ConsumerWidget {
  final String orderId;
  final ShipmentPlan plan;

  const _SummaryPanel({required this.orderId, required this.plan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<num?> costValue = ref.watch(costTotalProvider((orderId: orderId, planId: plan.id)));

    // Chưa tải xong hoặc lỗi thì hiện "—", không chặn màn
    String costText = '—';
    final num? cost = costValue.value;
    if (cost != null) {
      costText = formatMoney(cost);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _SummaryCell(
              title: 'Số chuyến',
              value: '${plan.trips.length}',
              big: true,
              note: plan.lowerBoundTrips > 0 ? 'tối thiểu ${plan.lowerBoundTrips}' : '',
            ),
          ),
          Expanded(
            child: _SummaryCell(
              title: 'Hàng',
              value: formatNumber(plan.totalKg),
              big: true,
              note: 'kg · ${plan.totalItems} kiện',
            ),
          ),
          Expanded(
            child: _SummaryCell(
              title: 'Dầu khứ hồi',
              value: costText,
              big: false,
              note: '',
              onTap: () {
                // Màn chi tiết tiền dầu (K3)
                context.push('/orders/$orderId/plans/${plan.id}/cost');
              },
              tapText: 'xem chi tiết',
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  final String title;
  final String value;
  // true: số to (22), false: số nhỏ hơn (16) cho số tiền dài
  final bool big;
  final String note;
  final VoidCallback? onTap;
  final String tapText;

  const _SummaryCell({
    required this.title,
    required this.value,
    required this.big,
    required this.note,
    this.onTap,
    this.tapText = '',
  });

  @override
  Widget build(BuildContext context) {
    const Color muted = Color(0xFFC9D2E3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 12, color: muted)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(fontSize: big ? 22 : 16, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        if (note.isNotEmpty) Text(note, style: const TextStyle(fontSize: 11, color: muted)),
        if (onTap != null)
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(tapText, style: const TextStyle(fontSize: 11, color: Color(0xFFF6C9A6))),
            ),
          ),
      ],
    );
  }
}

// Khung báo có chữ đậm ở đầu rồi chữ thường
class _NoticeBox extends StatelessWidget {
  final Color background;
  final Color foreground;
  final String title;
  final String text;

  const _NoticeBox({required this.background, required this.foreground, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: title, style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: text),
          ],
        ),
        style: TextStyle(fontSize: 13, height: 1.5, color: foreground),
      ),
    );
  }
}

// Thẻ một chuyến trong kế hoạch. Bấm mở chi tiết chuyến (K2)
class _TripCard extends StatelessWidget {
  final String orderId;
  final String planId;
  final PlanTrip trip;

  const _TripCard({required this.orderId, required this.planId, required this.trip});

  // Xe: "Xe tải 51C-900.01" hoặc "Sơ mi rơ moóc 51R-900.03 + đầu kéo 51D-900.02"
  String _vehicleText() {
    final PlanVehicle? carrier = trip.carrier;
    if (carrier == null) {
      return 'Chưa chọn xe';
    }
    String text = '${label(vehicleBaseTypeLabels, carrier.baseType)} ${carrier.plateNumber}';
    final PlanVehicle? tractor = trip.tractor;
    if (tractor != null) {
      text = '$text + đầu kéo ${tractor.plateNumber}';
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    // Nhãn đạt / không đạt
    String chipText = label(verdictLabels, trip.verdict);
    Color chipBackground = AppColors.okBackground;
    Color chipForeground = AppColors.okText;
    if (trip.verdict == 'Fail') {
      chipBackground = AppColors.errorBackground;
      chipForeground = AppColors.errorText;
    } else if (trip.verdict == 'Unchecked') {
      chipBackground = const Color(0xFFF2F4F7);
      chipForeground = AppColors.textMuted;
    } else if (trip.nearLimit) {
      chipText = '$chipText · sát giới hạn';
      chipBackground = AppColors.warnBackground;
      chipForeground = AppColors.warnText;
    }

    // Dòng số liệu: "8 kiện · 13.900 / 15.000 kg · đợt giao 1"
    String weightText = formatKg(trip.cargoKg);
    final PlanVehicle? carrier = trip.carrier;
    if (carrier != null && carrier.payloadKg > 0) {
      weightText = '${formatNumber(trip.cargoKg)} / ${formatKg(carrier.payloadKg)}';
    }
    final String detail = '${trip.itemCount} kiện · $weightText · đợt giao ${trip.deliveryWave}';

    final bool failed = trip.verdict == 'Fail';

    return Card(
      margin: EdgeInsets.zero,
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: failed ? const Color(0xFFF3B8B2) : AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // Chỉ truyền id, màn chi tiết chuyến tự gọi API (doc mục 1.5)
          context.push('/orders/$orderId/plans/$planId/trips/${trip.id}');
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Chuyến ${trip.sequence}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: chipBackground, borderRadius: BorderRadius.circular(999)),
                    child: Text(
                      chipText,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: chipForeground),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(_vehicleText(), style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 2),
              Text(detail, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
              // Cảnh báo đầu tiên của chuyến (vd quá tải cụm trục sau)
              if (trip.warnings.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    trip.warnings.first,
                    style: TextStyle(fontSize: 13, color: failed ? AppColors.errorText : AppColors.warnText),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Phần dưới màn: lý do khóa nút Duyệt, nút "Lên lại kế hoạch" và "Duyệt kế hoạch"
class _BottomBar extends StatelessWidget {
  final ShipmentPlan plan;
  final bool canRun;
  final bool canApprove;
  final bool busy;
  final String busyText;
  final VoidCallback onGenerate;
  final VoidCallback onApprove;

  const _BottomBar({
    required this.plan,
    required this.canRun,
    required this.canApprove,
    required this.busy,
    required this.busyText,
    required this.onGenerate,
    required this.onApprove,
  });

  @override
  Widget build(BuildContext context) {
    // Lý do chưa duyệt được (null: duyệt được)
    String? blockReason;
    final List<PlanTrip> failed = plan.failedTrips;
    if (!plan.isDraft) {
      blockReason = null;
    } else if (plan.isStale) {
      blockReason = 'Kế hoạch đã cũ: lên lại kế hoạch rồi mới duyệt được.';
    } else if (failed.isNotEmpty) {
      final List<String> numbers = <String>[];
      for (final PlanTrip trip in failed) {
        numbers.add('${trip.sequence}');
      }
      blockReason = 'Còn chuyến Không đạt: sửa chuyến ${numbers.join(', ')} rồi mới duyệt được.';
    }

    final List<Widget> buttons = <Widget>[];
    if (canRun) {
      buttons.add(
        Expanded(
          child: OutlinedButton(
            onPressed: busy ? null : onGenerate,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: AppColors.navy,
              side: const BorderSide(color: AppColors.inputBorder),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            child: const Text('Lên lại kế hoạch'),
          ),
        ),
      );
    }
    // Chỉ bản Nháp mới duyệt; có quyền duyệt mới thấy nút
    if (plan.isDraft && canApprove) {
      if (buttons.isNotEmpty) {
        buttons.add(const SizedBox(width: 10));
      }
      buttons.add(
        Expanded(
          child: FilledButton(
            onPressed: (busy || blockReason != null) ? null : onApprove,
            child: _BusyLabel(busy: busy, busyText: busyText, text: 'Duyệt kế hoạch'),
          ),
        ),
      );
    }

    if (buttons.isEmpty && (blockReason == null || !canApprove) && plan.isDraft) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (blockReason != null && canApprove)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(blockReason, style: const TextStyle(fontSize: 13, color: AppColors.errorText)),
              ),
            if (!plan.isDraft)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Kế hoạch này ${label(planStatusLabels, plan.status).toLowerCase()}.',
                  style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
              ),
            if (buttons.isNotEmpty) Row(children: buttons),
          ],
        ),
      ),
    );
  }
}
