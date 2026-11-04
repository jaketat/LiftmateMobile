// Q1: danh sách báo hỏng của công ty (mục "Báo hỏng xe" trong màn Thêm).
// Lọc chưa đóng / mới / đã nhận / đã xử lý. Mới nhất trước.
import 'package:flutter/cupertino.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/labels.dart';
import '../../core/theme.dart';
import '../../core/widgets/ios.dart';
import '../../core/widgets/ios_paged_sliver.dart';
import 'maintenance_api.dart';
import 'maintenance_providers.dart';

// Bốn cách lọc. "Chưa đóng" (khóa rỗng) là openOnly, ba cái kia lọc theo trạng thái.
const String _filterOpen = 'Open';
const String _filterAcknowledged = 'Acknowledged';
const String _filterResolved = 'Resolved';

class BreakdownListScreen extends ConsumerStatefulWidget {
  const BreakdownListScreen({super.key});

  @override
  ConsumerState<BreakdownListScreen> createState() => _BreakdownListScreenState();
}

class _BreakdownListScreenState extends ConsumerState<BreakdownListScreen> {
  final GlobalKey<IosPagedSliverState<BreakdownReport>> listKey = GlobalKey<IosPagedSliverState<BreakdownReport>>();
  // Mặc định xem báo chưa đóng: đây là việc cần làm hôm nay
  String filter = '';

  Future<void> refresh() async {
    ref.invalidate(openBreakdownCountProvider);
    await listKey.currentState?.reload();
  }

  // Màn chi tiết có thể vừa nhận hoặc đóng báo: về thì tải lại
  Future<void> openReport(BreakdownReport report) async {
    await context.push('/maintenance/breakdowns/${report.publicId}');
    if (mounted) await refresh();
  }

  @override
  Widget build(BuildContext context) {
    final int? openCount = ref.watch(openBreakdownCountProvider).value;
    return IosPage(
      title: t('maintenance.breakdownList.title'),
      onRefresh: refresh,
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: IosFilterBar<String>(
            options: <String?, String>{
              '': openCount == null
                  ? t('maintenance.breakdownList.notClosed')
                  : t('maintenance.breakdownList.notClosedCount', <String, Object?>{'count': openCount}),
              _filterOpen: label(breakdownStatusLabels, _filterOpen),
              _filterAcknowledged: label(breakdownStatusLabels, _filterAcknowledged),
              _filterResolved: label(breakdownStatusLabels, _filterResolved),
            },
            selected: filter,
            onSelected: (String? value) => setState(() => filter = value ?? ''),
          ),
        ),
        IosPagedSliver<BreakdownReport>(
          key: listKey,
          query: filter,
          // Chỉ lọc trạng thái khi chọn "Mới"/"Đã nhận"/"Đã xử lý"; "Chưa đóng" thì gửi openOnly
          fetchPage: (int pageNumber) => fetchBreakdownPage(
            pageNumber: pageNumber,
            status: filter,
            openOnly: filter.isEmpty,
            vehicleId: '',
          ),
          emptyText: t('maintenance.breakdownList.empty'),
          emptyIcon: CupertinoIcons.exclamationmark_triangle,
          footer: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              t('maintenance.breakdownList.footer'),
              style: TextStyle(fontSize: 13, height: 1.35, color: IosColors.secondaryLabel),
            ),
          ),
          itemBuilder: (BreakdownReport report) => BreakdownCard(report: report, onTap: () => openReport(report)),
        ),
      ],
    );
  }
}

/// Màu nhãn trạng thái báo hỏng: đã xử lý xanh, đã nhận cam, mới xanh đậm
Color breakdownStatusColor(String status) {
  if (status == 'Resolved') return IosColors.green;
  if (status == 'Acknowledged') return IosColors.orange;
  return AppColors.navy;
}

/// Thẻ một báo hỏng trong danh sách quản lý.
class BreakdownCard extends StatelessWidget {
  final BreakdownReport report;
  final VoidCallback onTap;

  const BreakdownCard({super.key, required this.report, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bool mustStop = report.severity == 'MustStop';
    // Báo "phải dừng" còn Mới thì xe đang bị chặn gán chuyến, nhắc người quản lý
    final bool blocksDispatch = mustStop && report.status == 'Open';

    final DateTime moment = DateTime.parse(report.reportedAt).toLocal();
    final DateTime now = DateTime.now();
    final String time = '${moment.hour.toString().padLeft(2, '0')}:${moment.minute.toString().padLeft(2, '0')}';
    final bool isToday = moment.year == now.year && moment.month == now.month && moment.day == now.day;
    final String whenText = isToday
        ? t('maintenance.breakdownList.todayAt', <String, Object?>{'time': time})
        : '${moment.day.toString().padLeft(2, '0')}/${moment.month.toString().padLeft(2, '0')} $time';

    return IosCard(
      onTap: onTap,
      borderColor: blocksDispatch ? IosColors.red.withValues(alpha: 0.45) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          IosIconBadge(
            icon: CupertinoIcons.exclamationmark_triangle_fill,
            color: report.status == 'Resolved' ? IosColors.green : (mustStop ? IosColors.red : IosColors.orange),
            size: 40,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(report.vehicleLabel, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text)),
                    ),
                    const SizedBox(width: 8),
                    IosPill(label(breakdownSeverityLabels, report.severity), color: mustStop ? IosColors.red : IosColors.orange),
                  ],
                ),
                const SizedBox(height: 4),
                Text(report.description, style: TextStyle(fontSize: 15, height: 1.4, color: AppColors.text)),
                const SizedBox(height: 4),
                Text(
                  // Ai đã nhận thì ghi tên người nhận thay vì mã đơn
                  report.acknowledgedByName.isNotEmpty
                      ? '${report.reportedByName} · $whenText · ${t('maintenance.breakdownList.ackedBy', <String, Object?>{'name': report.acknowledgedByName})}'
                      : '${report.reportedByName} · $whenText · ${report.orderCode}',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    IosPill(label(breakdownStatusLabels, report.status), color: breakdownStatusColor(report.status)),
                    if (blocksDispatch) IosPill(t('maintenance.breakdownList.blocksDispatch'), color: IosColors.red),
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
