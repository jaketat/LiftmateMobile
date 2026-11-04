// M6: báo cáo chi phí bảo trì theo khoảng ngày - tổng, định kỳ / sửa chữa, 5 xe tốn nhất.
// Chỉ tính lịch đã hoàn thành, theo ngày làm xong thật.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/labels.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ios.dart';
import '../orders/order_new_sheets.dart' show pickDateTime;
import 'maintenance_api.dart';
import 'maintenance_providers.dart';

// Khoảng ngày tối đa server cho phép
const int maxRangeDays = 730;

class CostReportScreen extends ConsumerStatefulWidget {
  const CostReportScreen({super.key});

  @override
  ConsumerState<CostReportScreen> createState() => _CostReportScreenState();
}

class _CostReportScreenState extends ConsumerState<CostReportScreen> {
  // Mặc định: từ 1/1 năm nay đến hôm nay
  late DateTime fromDate;
  late DateTime toDate;

  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    fromDate = DateTime(now.year, 1, 1);
    toDate = DateTime(now.year, now.month, now.day);
  }

  // Chọn một đầu của khoảng ngày bằng bánh xe iOS. Sai thứ tự hoặc quá 2 năm thì báo, không đổi.
  Future<void> pickEnd({required bool isFrom}) async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await pickDateTime(
      context,
      mode: CupertinoDatePickerMode.date,
      initial: isFrom ? fromDate : toDate,
      minimumDate: DateTime(now.year - 3),
      maximumDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null || !mounted) {
      return;
    }
    final DateTime day = DateTime(picked.year, picked.month, picked.day);
    final DateTime from = isFrom ? day : fromDate;
    final DateTime to = isFrom ? toDate : day;
    if (to.isBefore(from)) {
      showIosToast(context, t('maintenance.edit.endBeforeStart'), isError: true);
      return;
    }
    if (to.difference(from).inDays > maxRangeDays) {
      showIosToast(context, t('maintenance.costReport.rangeTooLong'), isError: true);
      return;
    }
    setState(() {
      fromDate = from;
      toDate = to;
    });
  }

  @override
  Widget build(BuildContext context) {
    final CostRange range = (from: _serverDate(fromDate), to: _serverDate(toDate));
    final AsyncValue<MaintenanceCostSummary> summaryValue = ref.watch(costSummaryProvider(range));
    final MaintenanceCostSummary? summary = summaryValue.value;

    return IosPage(
      title: t('maintenance.costReport.title'),
      onRefresh: () => ref.refresh(costSummaryProvider(range).future),
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: IosGroup(
            header: t('maintenance.costReport.rangeHelp'),
            headerIcon: CupertinoIcons.calendar,
            children: <Widget>[
              IosValueRow(label: t('maintenance.edit.from'), value: _show(fromDate), valueColor: AppColors.text, onTap: () => pickEnd(isFrom: true)),
              IosValueRow(label: t('maintenance.edit.to'), value: _show(toDate), valueColor: AppColors.text, onTap: () => pickEnd(isFrom: false)),
            ],
          ),
        ),
        if (summary == null)
          SliverFillRemaining(
            hasScrollBody: false,
            child: AsyncView<MaintenanceCostSummary>(
              value: summaryValue,
              onRetry: () => ref.invalidate(costSummaryProvider),
              builder: (MaintenanceCostSummary _) => const SizedBox.shrink(),
            ),
          )
        else
          SliverToBoxAdapter(child: summaryBody(summary)),
      ],
    );
  }

  Widget summaryBody(MaintenanceCostSummary summary) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: TotalCard(summary: summary),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Row(
            spacing: 12,
            children: <Widget>[
              Expanded(child: StatCard(label: t('maintenance.costReport.scheduledCount'), value: '${summary.scheduledCount}')),
              Expanded(
                child: StatCard(
                  label: t('maintenance.costReport.overdueCount'),
                  value: '${summary.overdueCount}',
                  isDanger: summary.overdueCount > 0,
                ),
              ),
            ],
          ),
        ),
        if (summary.topVehicles.isNotEmpty)
          IosGroup(
            header: t('maintenance.costReport.topVehicles'),
            headerIcon: CupertinoIcons.car_detailed,
            children: <Widget>[
              for (final VehicleMaintenanceCost cost in summary.topVehicles)
                IosValueRow(
                  label: t('maintenance.costReport.serviceCount', <String, Object?>{'vehicle': cost.vehicleLabel, 'count': cost.serviceCount}),
                  value: formatMoney(cost.totalCost),
                  valueColor: AppColors.text,
                ),
            ],
          ),
        if (summary.costByVehicleBaseType.isNotEmpty)
          IosGroup(
            header: t('maintenance.costReport.byBaseType'),
            headerIcon: CupertinoIcons.square_grid_2x2_fill,
            children: <Widget>[
              for (final MapEntry<String, double> entry in summary.costByVehicleBaseType.entries)
                IosValueRow(label: label(vehicleBaseTypeLabels, entry.key), value: formatMoney(entry.value), valueColor: AppColors.text),
            ],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
          child: Text(t('maintenance.costReport.note'), style: TextStyle(fontSize: 13, height: 1.35, color: IosColors.secondaryLabel)),
        ),
      ],
    );
  }
}

/// Thẻ xanh đậm: tổng tiền và tỷ lệ định kỳ / sửa chữa.
class TotalCard extends StatelessWidget {
  final MaintenanceCostSummary summary;

  const TotalCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    // Không có lần nào xong việc thì không chia tỷ lệ, thanh để trống
    final double ratio =
        summary.totalCost <= 0 ? 0 : (summary.periodicCost / summary.totalCost).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[AppColors.navy, Color.lerp(AppColors.navy, Colors.black, 0.25)!],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x290C2858), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            t('maintenance.costReport.total', <String, Object?>{'count': summary.completedCount}),
            style: const TextStyle(fontSize: 13, color: Color(0xFFBCC7DC)),
          ),
          const SizedBox(height: 6),
          Text(
            formatMoney(summary.totalCost),
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Row(
                children: <Widget>[
                  Expanded(flex: (ratio * 1000).round().clamp(0, 1000), child: Container(color: Colors.white)),
                  Expanded(
                    flex: ((1 - ratio) * 1000).round().clamp(0, 1000),
                    child: Container(color: AppColors.orange),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: <Widget>[
              LegendDot(color: Colors.white, text: t('maintenance.costReport.periodic', <String, Object?>{'amount': formatMoney(summary.periodicCost)})),
              LegendDot(color: AppColors.orange, text: t('maintenance.costReport.repair', <String, Object?>{'amount': formatMoney(summary.repairCost)})),
            ],
          ),
        ],
      ),
    );
  }
}

class LegendDot extends StatelessWidget {
  final Color color;
  final String text;

  const LegendDot({super.key, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFFD5DCEA))),
      ],
    );
  }
}

/// Thẻ số nhỏ: "Lịch chưa làm  4"
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final bool isDanger;

  const StatCard({super.key, required this.label, required this.value, this.isDanger = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: isDanger ? Border.all(color: IosColors.red.withValues(alpha: 0.45), width: 1.5) : null,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: isDanger ? AppColors.errorText : AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

// Ngày server nhận: yyyy-MM-dd
String _serverDate(DateTime day) {
  return '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
}

// Ngày hiện cho người dùng: dd/MM/yyyy
String _show(DateTime day) {
  return '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}/${day.year}';
}