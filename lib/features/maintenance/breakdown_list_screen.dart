// Q1: danh sách báo hỏng của công ty (mục "Báo hỏng xe" trong màn Thêm).
// Lọc chưa đóng / mới / đã nhận / đã xử lý. Mới nhất trước.
import 'package:flutter/material.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push
import 'package:go_router/go_router.dart';

import '../../core/api/paged_result.dart';
import '../../core/i18n.dart';
import '../../core/labels.dart';
import '../../core/theme.dart';
import 'maintenance_api.dart';
import 'maintenance_providers.dart';
import 'widgets.dart';

// Bốn cách lọc. "Chưa đóng" là openOnly, ba cái kia lọc theo trạng thái.
const String _filterOpen = 'Open';
const String _filterAcknowledged = 'Acknowledged';
const String _filterResolved = 'Resolved';

class BreakdownListScreen extends ConsumerStatefulWidget {
  const BreakdownListScreen({super.key});

  @override
  ConsumerState<BreakdownListScreen> createState() => _BreakdownListScreenState();
}

class _BreakdownListScreenState extends ConsumerState<BreakdownListScreen> {
  final List<BreakdownReport> reports = <BreakdownReport>[];
  int pageNumber = 1;
  bool hasMore = false;
  bool isLoadingMore = false;
  // Mặc định xem báo chưa đóng: đây là việc cần làm hôm nay
  String filter = '';

  void applyFilter() {
    setState(() {
      pageNumber = 1;
      reports.clear();
      hasMore = false;
    });
  }

  void loadMore() {
    if (isLoadingMore || !hasMore) {
      return;
    }
    setState(() {
      isLoadingMore = true;
      pageNumber = pageNumber + 1;
    });
  }

  // Kiểu Future vì RefreshIndicator trong PagedListView đòi hàm trả Future
  Future<void> refresh() async {
    setState(() {
      pageNumber = 1;
      reports.clear();
      hasMore = false;
      isLoadingMore = false;
    });
    ref.invalidate(breakdownsPageProvider);
    ref.invalidate(openBreakdownCountProvider);
  }

  @override
  Widget build(BuildContext context) {
    // Chỉ lọc trạng thái khi chọn "Mới"/"Đã nhận"/"Đã xử lý"; "Chưa đóng" thì gửi openOnly
    final bool isOpenOnly = filter.isEmpty;
    final BreakdownFilter currentFilter = (
      pageNumber: pageNumber,
      status: filter,
      openOnly: isOpenOnly,
      vehicleId: '',
    );

    ref.listen(breakdownsPageProvider(currentFilter),
        (AsyncValue<PagedResult<BreakdownReport>>? previous,
            AsyncValue<PagedResult<BreakdownReport>> next) {
      next.whenData((PagedResult<BreakdownReport> page) {
        if (!mounted) {
          return;
        }
        setState(() {
          if (currentFilter.pageNumber == 1) {
            reports.clear();
          }
          reports.addAll(page.items);
          hasMore = page.hasNextPage;
          isLoadingMore = false;
        });
      });
    });

    final AsyncValue<PagedResult<BreakdownReport>> pageValue =
        ref.watch(breakdownsPageProvider(currentFilter));
    final AsyncValue<int> openCountValue = ref.watch(openBreakdownCountProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t('maintenance.breakdownList.title'))),
      body: Column(
        children: <Widget>[
          const SizedBox(height: 12),
          FilterPills<String>(
            options: <({String label, String value})>[
              (
                value: '',
                label: openCountValue.value == null
                    ? t('maintenance.breakdownList.notClosed')
                    : t('maintenance.breakdownList.notClosedCount', <String, Object?>{'count': openCountValue.value}),
              ),
              (value: _filterOpen, label: label(breakdownStatusLabels, 'Open')),
              (value: _filterAcknowledged, label: label(breakdownStatusLabels, _filterAcknowledged)),
              (value: _filterResolved, label: label(breakdownStatusLabels, _filterResolved)),
            ],
            selected: filter,
            onChanged: (String value) {
              setState(() {
                filter = value;
              });
              applyFilter();
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: PagedListView<BreakdownReport>(
              firstPage: pageValue,
              items: reports,
              isLoadingMore: isLoadingMore,
              hasMore: hasMore,
              onRefresh: refresh,
              onLoadMore: loadMore,
              emptyText: t('maintenance.breakdownList.empty'),
              footer: Padding(
                padding: EdgeInsets.fromLTRB(20, 6, 20, 24),
                child: NoteText(
                  t('maintenance.breakdownList.footer'),
                ),
              ),
              itemBuilder: (BreakdownReport report) {
                return BreakdownCard(report: report);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Thẻ một báo hỏng trong danh sách quản lý.
class BreakdownCard extends StatelessWidget {
  final BreakdownReport report;

  const BreakdownCard({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final bool mustStop = report.severity == 'MustStop';
    // Báo "phải dừng" còn Mới thì xe đang bị chặn gán chuyến, nhắc người quản lý
    final bool blocksDispatch = mustStop && report.status == 'Open';

    final List<Widget> chips = <Widget>[
      ToneChip(label(breakdownStatusLabels, report.status), tone: _statusTone(report.status)),
      if (blocksDispatch) ToneChip(t('maintenance.breakdownList.blocksDispatch'), tone: Tone.warn),
    ];

    final DateTime moment = DateTime.parse(report.reportedAt).toLocal();
    final DateTime now = DateTime.now();
    final String time =
        '${moment.hour.toString().padLeft(2, '0')}:${moment.minute.toString().padLeft(2, '0')}';
    final bool isToday =
        moment.year == now.year && moment.month == now.month && moment.day == now.day;
    final String whenText = isToday
        ? t('maintenance.breakdownList.todayAt', <String, Object?>{'time': time})
        : '${moment.day.toString().padLeft(2, '0')}/${moment.month.toString().padLeft(2, '0')} $time';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: blocksDispatch ? AppColors.errorBorder : AppColors.border),
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
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text),
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
                style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.text),
              ),
              const SizedBox(height: 6),
              Text(
                // Ai đã nhận thì ghi tên người nhận thay vì giờ nhận
                report.acknowledgedByName.isNotEmpty
                    ? '${report.reportedByName} · $whenText · ${t('maintenance.breakdownList.ackedBy', <String, Object?>{'name': report.acknowledgedByName})}'
                    : '${report.reportedByName} · $whenText · ${report.orderCode}',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
              if (chips.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 6, children: chips),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Tone _statusTone(String status) {
  if (status == 'Resolved') {
    return Tone.ok;
  }
  if (status == 'Acknowledged') {
    return Tone.warn;
  }
  return Tone.neutral;
}