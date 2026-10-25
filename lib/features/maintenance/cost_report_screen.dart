// M6: báo cáo chi phí bảo trì theo khoảng ngày - tổng, đồng xơ, 5 xe tốn nhất.
// Chỉ tính lịch đã hoàn thành, theo ngày làm xong thật.
import 'package:flutter/material.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/labels.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import 'maintenance_api.dart';
import 'maintenance_providers.dart';
import 'widgets.dart';

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
    toDate = now;
  }

  Future<void> pickRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: fromDate, end: toDate),
      firstDate: DateTime(DateTime.now().year - 3),
      lastDate: DateTime(DateTime.now().year + 1),
      locale: const Locale('vi'),
      helpText: 'Khoảng ngày làm xong',
    );
    if (picked == null || !mounted) {
      return;
    }
    if (picked.end.difference(picked.start).inDays > maxRangeDays) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Khoảng ngày tối đa 2 năm.')),
      );
      return;
    }
    setState(() {
      fromDate = picked.start;
      toDate = picked.end;
    });
  }

  @override
  Widget build(BuildContext context) {
    final CostRange range = (
      from: _serverDate(fromDate),
      to: _serverDate(toDate),
    );
    final AsyncValue<MaintenanceCostSummary> summaryValue = ref.watch(costSummaryProvider(range));

    return Scaffold(
      appBar: AppBar(title: const Text('Chi phí bảo trì')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          GestureDetector(
            onTap: pickRange,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppColors.inputBorder),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.calendar_today_outlined, size: 17, color: AppColors.textMuted),
                  const SizedBox(width: 10),
                  Text(
                    '${_show(fromDate)} – ${_show(toDate)}',
                    style: const TextStyle(fontSize: 15, color: AppColors.text),
                  ),
                  const Spacer(),
                  const Icon(Icons.edit_calendar_outlined, size: 18, color: AppColors.navy),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          AsyncView<MaintenanceCostSummary>(
            value: summaryValue,
            onRetry: () {
              ref.invalidate(costSummaryProvider);
            },
            builder: (MaintenanceCostSummary summary) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TotalCard(summary: summary),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: StatCard(label: 'Lịch chưa làm', value: '${summary.scheduledCount}'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatCard(
                          label: 'Trong đó quá hạn',
                          value: '${summary.overdueCount}',
                          isDanger: summary.overdueCount > 0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (summary.topVehicles.isNotEmpty) ...[
                    const SectionHeading('5 xe tốn nhất'),
                    const SizedBox(height: 10),
                    SectionCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      children: <Widget>[
                        for (final VehicleMaintenanceCost cost in summary.topVehicles)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    '${cost.vehicleLabel} · ${cost.serviceCount} lần',
                                    style: const TextStyle(fontSize: 14, color: AppColors.text),
                                  ),
                                ),
                                Text(
                                  formatMoney(cost.totalCost),
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (summary.costByVehicleBaseType.isNotEmpty) ...[
                    const SectionHeading('Theo loại xe'),
                    const SizedBox(height: 10),
                    SectionCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      children: <Widget>[
                        for (final MapEntry<String, double> entry in summary.costByVehicleBaseType.entries)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    label(vehicleBaseTypeLabels, entry.key),
                                    style: const TextStyle(fontSize: 14, color: AppColors.text),
                                  ),
                                ),
                                Text(
                                  formatMoney(entry.value),
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  const NoteText(
                    'Tính theo ngày làm xong thật, chỉ lịch đã hoàn thành, gồm cả xe đã xóa. '
                    'Khoảng ngày tối đa 2 năm.',
                  ),
                ],
              );
            },
          ),
        ],
      ),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Tổng chi phí thật · ${summary.completedCount} lần làm xong',
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
              LegendDot(color: Colors.white, text: 'Định kỳ ${formatMoney(summary.periodicCost)}'),
              LegendDot(color: AppColors.orange, text: 'Sửa chữa ${formatMoney(summary.repairCost)}'),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: isDanger ? const Color(0xFFF3B5AE) : AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
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