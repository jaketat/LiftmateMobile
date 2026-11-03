// K1: kế hoạch chia chuyến của một đơn (theo màn N3-KeHoach trên canvas)
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
      _busyText = t('planning.plan.busyGenerating');
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
      _busyText = t('planning.plan.busyApproving');
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
      subtitle = t('planning.plan.version', <String, Object?>{
        'version': plan.version,
        'status': label(planStatusLabels, plan.status),
      });
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
            Text(t('planning.plan.title'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            if (subtitle.isNotEmpty)
              Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
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
        const SizedBox(width: 16, height: 16, child: CupertinoActivityIndicator()),
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
            Text(
              t('planning.plan.noPlan'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              t('planning.plan.noPlanHint'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            // Không có quyền chạy kế hoạch thì ẩn nút (doc mục 2.8)
            if (canRun)
              FilledButton(
                onPressed: busy ? null : onGenerate,
                child: _BusyLabel(busy: busy, busyText: busyText, text: t('planning.plan.generate')),
              )
            else
              Text(
                t('planning.plan.noPermission'),
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
        _NoticeBox(
          background: AppColors.warnBackground,
          foreground: AppColors.warnText,
          title: t('planning.plan.staleTitle'),
          text: ' ${t('planning.plan.staleText')}',
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
          title: t('planning.plan.unplanned', <String, Object?>{'count': count}),
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
      String text = ' ${t('planning.plan.pendingDefault')}';
      if (dates.isNotEmpty) {
        text = ' ${t('planning.plan.pendingDates', <String, Object?>{'dates': dates.join(', ')})}';
      }
      children.add(const SizedBox(height: 10));
      children.add(
        _NoticeBox(
          background: AppColors.warnBackground,
          foreground: AppColors.warnText,
          title: t('planning.plan.pending', <String, Object?>{'count': count}),
          text: text,
        ),
      );
    }

    if (plan.trips.isEmpty) {
      children.add(const SizedBox(height: 24));
      children.add(
        Center(child: Text(t('planning.plan.noTrips'), style: TextStyle(color: AppColors.textMuted))),
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
              title: t('planning.plan.tripCount'),
              value: '${plan.trips.length}',
              big: true,
              note: plan.lowerBoundTrips > 0 ? t('planning.plan.atLeast', <String, Object?>{'count': plan.lowerBoundTrips}) : '',
            ),
          ),
          Expanded(
            child: _SummaryCell(
              title: t('tripDetail.info.cargo'),
              value: formatNumber(plan.totalKg),
              big: true,
              note: t('planning.plan.cargoNote', <String, Object?>{'count': plan.totalItems}),
            ),
          ),
          Expanded(
            child: _SummaryCell(
              title: t('planning.cost.fuelRound'),
              value: costText,
              big: false,
              note: '',
              onTap: () {
                // Màn chi tiết tiền dầu (K3)
                context.push('/orders/$orderId/plans/${plan.id}/cost');
              },
              tapText: t('planning.plan.viewDetails'),
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
      return t('planning.noVehicle');
    }
    String text = '${label(vehicleBaseTypeLabels, carrier.baseType)} ${carrier.plateNumber}';
    final PlanVehicle? tractor = trip.tractor;
    if (tractor != null) {
      text = t('planning.withTractor', <String, Object?>{'vehicle': text, 'plate': tractor.plateNumber});
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
      chipBackground = AppColors.fillSoft;
      chipForeground = AppColors.textMuted;
    } else if (trip.nearLimit) {
      chipText = t('planning.nearLimit', <String, Object?>{'verdict': chipText});
      chipBackground = AppColors.warnBackground;
      chipForeground = AppColors.warnText;
    }

    // Dòng số liệu: "8 kiện · 13.900 / 15.000 kg · đợt giao 1"
    String weightText = formatKg(trip.cargoKg);
    final PlanVehicle? carrier = trip.carrier;
    if (carrier != null && carrier.payloadKg > 0) {
      weightText = '${formatNumber(trip.cargoKg)} / ${formatKg(carrier.payloadKg)}';
    }
    final String detail = t('planning.plan.tripDetail', <String, Object?>{
      'count': trip.itemCount,
      'weight': weightText,
      'wave': trip.deliveryWave,
    });

    final bool failed = trip.verdict == 'Fail';

    return Card(
      margin: EdgeInsets.zero,
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: failed ? AppColors.errorBorder : AppColors.border),
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
                  Text(t('planning.tripNumber', <String, Object?>{'sequence': trip.sequence}), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
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
              Text(detail, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
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
      blockReason = t('planning.plan.blockStale');
    } else if (failed.isNotEmpty) {
      final List<String> numbers = <String>[];
      for (final PlanTrip trip in failed) {
        numbers.add('${trip.sequence}');
      }
      blockReason = t('planning.plan.blockFailed', <String, Object?>{'numbers': numbers.join(', ')});
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
              side: BorderSide(color: AppColors.inputBorder),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            child: Text(t('planning.plan.regenerate')),
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
            child: _BusyLabel(busy: busy, busyText: busyText, text: t('planning.plan.approve')),
          ),
        ),
      );
    }

    if (buttons.isEmpty && (blockReason == null || !canApprove) && plan.isDraft) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
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
                child: Text(blockReason, style: TextStyle(fontSize: 13, color: AppColors.errorText)),
              ),
            if (!plan.isDraft)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  t('planning.plan.statusNote', <String, Object?>{'status': label(planStatusLabels, plan.status).toLowerCase()}),
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
              ),
            if (buttons.isNotEmpty) Row(children: buttons),
          ],
        ),
      ),
    );
  }
}
