// M1: danh sách lịch bảo trì (tab "Bảo trì" của quản lý, path /maintenance).
// Lọc trạng thái, loại, quá hạn. Lịch quá hạn có nhánh đỏ.
import 'package:flutter/material.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState, AsyncValue, WidgetRef
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push
import 'package:go_router/go_router.dart';

import '../../core/api/paged_result.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/labels.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../auth/session_provider.dart';
import 'maintenance_api.dart';
import 'maintenance_providers.dart';
import 'widgets.dart';

class MaintenanceListScreen extends ConsumerStatefulWidget {
  const MaintenanceListScreen({super.key});

  @override
  ConsumerState<MaintenanceListScreen> createState() => _MaintenanceListScreenState();
}

class _MaintenanceListScreenState extends ConsumerState<MaintenanceListScreen> {
  // Các trang đã tải gộp lại. server phân trang nên không tải hết một lúc.
  final List<MaintenanceRecord> records = <MaintenanceRecord>[];
  int pageNumber = 1;
  bool hasMore = false;
  bool isLoadingMore = false;

  String status = 'Scheduled';
  String kind = '';
  String searchTerm = '';
  final TextEditingController searchController = TextEditingController();

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  // Đổi bộ lọc thì về trang 1 và bỏ danh sách cũ
  void applyFilter() {
    setState(() {
      pageNumber = 1;
      records.clear();
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
      records.clear();
      hasMore = false;
      isLoadingMore = false;
    });
    ref.invalidate(maintenancePageProvider);
    ref.invalidate(dueAlertsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final Session? session = ref.watch(sessionProvider).value;
    final AsyncValue<List<MaintenanceDueAlert>> alertsValue = ref.watch(dueAlertsProvider);

    // "Quá hạn" là một cách lọc riêng, không lọc theo trạng thái
    final bool isOverdueFilter = status == 'Overdue';
    final MaintenanceFilter filter = (
      pageNumber: pageNumber,
      status: isOverdueFilter ? '' : status,
      kind: kind,
      searchTerm: searchTerm,
      overdueOnly: isOverdueFilter,
      vehicleId: '',
    );

    // Trang vừa tải xong thì gộp vào danh sách. Nghe ở đây để không sửa state trong build.
    ref.listen(maintenancePageProvider(filter),
        (AsyncValue<PagedResult<MaintenanceRecord>>? previous,
            AsyncValue<PagedResult<MaintenanceRecord>> next) {
      next.whenData((PagedResult<MaintenanceRecord> page) {
        if (!mounted) {
          return;
        }
        setState(() {
          if (filter.pageNumber == 1) {
            records.clear();
          }
          records.addAll(page.items);
          hasMore = page.hasNextPage;
          isLoadingMore = false;
        });
      });
    });

    final AsyncValue<PagedResult<MaintenanceRecord>> pageValue =
        ref.watch(maintenancePageProvider(filter));

    // Dải cảnh báo đền hạn (M4): có xe đến hạn mới hiện
    final List<MaintenanceDueAlert>? alerts = alertsValue.value;
    final Widget? dueBanner = (alerts == null || alerts.isEmpty)
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Material(
              // Material trong suốt để InkWell vẽ được gợn sóng trên dải cảnh báo
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () {
                  context.push('/maintenance/due-alerts');
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.warnBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.warning_amber_outlined, size: 20, color: AppColors.warnText),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t('maintenance.list.dueBanner', <String, Object?>{'count': alerts.length}),
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.warnText),
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 20, color: AppColors.warnText),
                    ],
                  ),
                ),
              ),
            ),
          );

    final List<Widget> actions = <Widget>[
      // Báo cáo chi phí (M6): chỉ người xem được tiền mới thấy
      if (session != null &&
          (session.can('Vehicles.Maintenance') || session.can('Reports.ViewFinance')))
        IconButton(
          tooltip: t('maintenance.list.costReport'),
          icon: const Icon(Icons.bar_chart_outlined),
          onPressed: () {
            context.push('/maintenance/cost-report');
          },
        ),
      // Lập lịch (M2)
      if (session != null && session.can('Vehicles.Maintenance'))
        IconButton(
          tooltip: t('maintenance.list.schedule'),
          icon: const Icon(Icons.add),
          onPressed: () {
            context.push('/maintenance/new');
          },
        ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(t('maintenance.list.title')), actions: actions),
      body: Column(
        children: <Widget>[
          // Dải cảnh báo đền hạn (M4): có xe đến hạn mới hiện
          ?dueBanner,
          const SizedBox(height: 8),
          FilterPills<String>(
            options: <({String label, String value})>[
              (value: 'Scheduled', label: label(maintenanceStatusLabels, 'Scheduled')),
              (value: 'Overdue', label: t('maintenance.list.overdue')),
              (value: 'Completed', label: label(maintenanceStatusLabels, 'Completed')),
              (value: 'Cancelled', label: label(maintenanceStatusLabels, 'Cancelled')),
            ],
            selected: status,
            onChanged: (String value) {
              setState(() {
                status = value;
              });
              applyFilter();
            },
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: TextField(
                      controller: searchController,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: t('maintenance.list.searchHint'),
                        hintStyle: const TextStyle(fontSize: 13),
                        prefixIcon: Icon(Icons.search, size: 19, color: AppColors.textMuted),
                        suffixIcon: searchTerm.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close, size: 17),
                                onPressed: () {
                                  searchController.clear();
                                  setState(() {
                                    searchTerm = '';
                                  });
                                  applyFilter();
                                },
                              ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onSubmitted: (String value) {
                        setState(() {
                          searchTerm = value.trim();
                        });
                        applyFilter();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Lọc theo loại: định kỳ hay sửa chữa
                SizedBox(
                  height: 44,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      border: Border.all(color: AppColors.inputBorder),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: kind,
                        isDense: true,
                        icon: const Icon(Icons.arrow_drop_down, size: 20),
                        style: TextStyle(fontSize: 14, color: AppColors.text),
                        items: <DropdownMenuItem<String>>[
                          DropdownMenuItem<String>(value: '', child: Text(t('maintenance.list.allKinds'))),
                          DropdownMenuItem<String>(value: 'Periodic', child: Text(label(maintenanceKindLabels, 'Periodic'))),
                          DropdownMenuItem<String>(value: 'Repair', child: Text(label(maintenanceKindLabels, 'Repair'))),
                        ],
                        onChanged: (String? value) {
                          setState(() {
                            kind = value ?? '';
                          });
                          applyFilter();
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: PagedListView<MaintenanceRecord>(
              firstPage: pageValue,
              items: records,
              isLoadingMore: isLoadingMore,
              hasMore: hasMore,
              onRefresh: refresh,
              onLoadMore: loadMore,
              emptyText: t('maintenance.list.empty'),
              footer: Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: NoteText(t('maintenance.list.footer')),
              ),
              itemBuilder: (MaintenanceRecord record) {
                return MaintenanceCard(record: record);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Thẻ một lịch: tên lịch, biển xe, ngày · loại · chi phí.
/// Lịch quá hạn thì viền đỏ nền hồng, để lướt xuống thấy ngay.
class MaintenanceCard extends StatelessWidget {
  final MaintenanceRecord record;

  const MaintenanceCard({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    final bool isOverdue = record.isOverdue && record.status == 'Scheduled';
    final String kindText = label(maintenanceKindLabels, record.kind);

    // Lịch sửa chữa nền hơi kem cho dễ phân biệt với lịch định kỳ
    final Color background = isOverdue
        ? AppColors.errorBackground
        : (record.kind == 'Repair' ? AppColors.surface : AppColors.surface);
    final Color borderColor = isOverdue ? AppColors.errorBorder : AppColors.border;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        // Material trong suốt để InkWell vẽ được gợn sóng ngay trên thẻ
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            context.push('/maintenance/${record.publicId}');
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      record.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isOverdue ? AppColors.errorText : AppColors.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Nhãn góc trên: quá hạn thì ưu tiên hiện quá hạn, không hiện loại
                  isOverdue
                      ? ToneChip(t('maintenance.list.overdue'), tone: Tone.danger)
                      : (record.kind == 'Repair'
                          ? ToneChip(kindText, tone: Tone.warn)
                          : ToneChip(kindText, tone: Tone.neutral)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                record.vehicleLabel,
                style: TextStyle(
                  fontSize: 14,
                  color: isOverdue ? AppColors.errorText : AppColors.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                t('maintenance.list.cardLine', <String, Object?>{
                  'start': formatDate(record.startDate),
                  'end': formatDate(record.endDate),
                  'kind': kindText.toLowerCase(),
                  'cost': record.estimatedCost == null ? '--' : formatMoney(record.estimatedCost),
                }),
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}