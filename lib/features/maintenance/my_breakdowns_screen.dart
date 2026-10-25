// T6: tab "Báo hỏng" của tài xế - 50 báo hồng gần nhất do mình gửi.
// Bấm một báo thì xem tiến độ; báo mới gửi từ nút "Báo hồng xe" trong chi tiết chuyến.
import 'package:flutter/material.dart';
// Riverpod: ConsumerWidget, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push
import 'package:go_router/go_router.dart';

import '../../core/labels.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import 'maintenance_api.dart';
import 'maintenance_providers.dart';
import 'widgets.dart';

const List<String> _stepLabels = <String>['Đã gửi', 'Quản lý đã nhận', 'Đã xử lý'];

class MyBreakdownsScreen extends ConsumerWidget {
  const MyBreakdownsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<BreakdownReport>> reportsValue = ref.watch(myBreakdownsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Bảo hồng của tôi')),
      // Lối tạo báo khi không mở từ chi tiết chuyến: bấm vào đây rồi chọn chuyến
      floatingActionButton: FloatingActionButton(
        tooltip: 'Báo hồng xe',
        onPressed: () {
          context.push('/driver/breakdowns/new');
        },
        child: const Icon(Icons.add),
      ),
      body: AsyncView<List<BreakdownReport>>(
        value: reportsValue,
        onRetry: () {
          ref.invalidate(myBreakdownsProvider);
        },
        isEmpty: (List<BreakdownReport> reports) {
          return reports.isEmpty;
        },
        emptyText: 'Bạn chưa báo hỏng xe lần nào.',
        builder: (List<BreakdownReport> reports) {
          final List<Widget> children = <Widget>[];
          for (final BreakdownReport report in reports) {
            children.add(MyBreakdownCard(report: report));
          }
          children.add(
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: NoteText(
                "Báo mới gửi từ nút 'Báo hồng xe' trong chi tiết chuyến. Hiện 50 báo gần nhất.",
              ),
            ),
          );
          return RefreshIndicator(
            onRefresh: () {
              return ref.refresh(myBreakdownsProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              children: children,
            ),
          );
        },
      ),
    );
  }
}

/// Thẻ một báo của tôi: biển xe, mức độ, mô tả, và thanh 3 bước.
class MyBreakdownCard extends StatelessWidget {
  final BreakdownReport report;

  const MyBreakdownCard({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final bool mustStop = report.severity == 'MustStop';

    final List<String> parts = <String>[
      '${_momentText(report.reportedAt)} · ${report.orderCode}',
      if (report.photoUrls.isNotEmpty) '${report.photoUrls.length} ảnh',
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: mustStop ? const Color(0xFFF3B5AE) : AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        // Material trong suốt để InkWell vẽ được gợn sóng ngay trên thẻ
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            context.push('/maintenance/breakdowns/${report.publicId}');
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      report.vehicleLabel,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ToneChip(
                    label(breakdownSeverityLabels, report.severity),
                    tone: mustStop ? Tone.danger : Tone.warn,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                report.description,
                style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.text),
              ),
              const SizedBox(height: 6),
              Text(
                'Gửi ${parts.join(' · ')}',
                style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              BreakdownStepBar(currentStep: report.progressStep, labels: _stepLabels),
            ],
          ),
        ),
      ),
    );
  }
}

/// "hôm nay 09:12" nếu gửi trong ngày, còn lại thì "12/10 09:12".
String _momentText(String isoText) {
  final DateTime moment = DateTime.parse(isoText).toLocal();
  final DateTime now = DateTime.now();
  final String time =
      '${moment.hour.toString().padLeft(2, '0')}:${moment.minute.toString().padLeft(2, '0')}';
  final bool isToday =
      moment.year == now.year && moment.month == now.month && moment.day == now.day;
  if (isToday) {
    return 'hôm nay $time';
  }
  return '${moment.day.toString().padLeft(2, '0')}/${moment.month.toString().padLeft(2, '0')} $time';
}