// M1: danh sách lịch bảo trì (tab "Bảo trì" của quản lý, path /maintenance).
// Lọc trạng thái, loại, quá hạn. Lịch quá hạn viền đỏ.
import 'dart:async';

import 'package:flutter/cupertino.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState, AsyncValue, WidgetRef
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/labels.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/ios.dart';
import '../../core/widgets/ios_paged_sliver.dart';
import '../auth/session_provider.dart';
import 'maintenance_api.dart';
import 'maintenance_providers.dart';

class MaintenanceListScreen extends ConsumerStatefulWidget {
  const MaintenanceListScreen({super.key});

  @override
  ConsumerState<MaintenanceListScreen> createState() => _MaintenanceListScreenState();
}

class _MaintenanceListScreenState extends ConsumerState<MaintenanceListScreen> {
  final GlobalKey<IosPagedSliverState<MaintenanceRecord>> listKey = GlobalKey<IosPagedSliverState<MaintenanceRecord>>();
  // "Overdue" là một cách lọc riêng, không lọc theo trạng thái
  String status = 'Scheduled';
  String? kind;
  String searchTerm = '';
  // Gõ xong 0,35 giây mới tìm, đỡ gọi API mỗi phím
  Timer? searchDebounce;

  @override
  void dispose() {
    searchDebounce?.cancel();
    super.dispose();
  }

  void onSearch(String text) {
    searchDebounce?.cancel();
    searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (text.trim() != searchTerm) setState(() => searchTerm = text.trim());
    });
  }

  Future<void> refresh() async {
    ref.invalidate(dueAlertsProvider);
    await listKey.currentState?.reload();
  }

  // Màn con có thể vừa sửa, hoàn thành hoặc hủy lịch: về thì tải lại
  Future<void> openAndReload(String path) async {
    await context.push(path);
    if (mounted) await refresh();
  }

  @override
  Widget build(BuildContext context) {
    final Session? session = ref.watch(sessionProvider).value;
    final List<MaintenanceDueAlert>? alerts = ref.watch(dueAlertsProvider).value;
    final bool canSchedule = session?.can('Vehicles.Maintenance') ?? false;
    // Báo cáo chi phí (M6): chỉ người xem được tiền mới thấy
    final bool canSeeCost = canSchedule || (session?.can('Reports.ViewFinance') ?? false);
    final bool isOverdueFilter = status == 'Overdue';

    return IosPage(
      title: t('maintenance.list.title'),
      inlineTitle: true,
      onRefresh: refresh,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (canSeeCost)
            IosGlassIconButton(
              icon: CupertinoIcons.chart_bar_alt_fill,
              nativeSymbol: 'chart.bar.fill',
              tooltip: t('maintenance.list.costReport'),
              onPressed: () => context.push('/maintenance/cost-report'),
            ),
          // Lập lịch (M2)
          if (canSchedule) ...<Widget>[
            const SizedBox(width: 8),
            IosGlassIconButton(
              icon: CupertinoIcons.add,
              nativeSymbol: 'plus',
              tooltip: t('maintenance.list.schedule'),
              onPressed: () => openAndReload('/maintenance/new'),
            ),
          ],
        ],
      ),
      slivers: <Widget>[
        // Dải cảnh báo đến hạn (M4): có xe đến hạn mới hiện
        if (alerts != null && alerts.isNotEmpty)
          SliverToBoxAdapter(
            child: IosGroup(
              children: <Widget>[
                IosRow(
                  icon: CupertinoIcons.exclamationmark_triangle_fill,
                  iconColor: IosColors.orange,
                  title: t('maintenance.list.dueBanner', <String, Object?>{'count': alerts.length}),
                  onTap: () => openAndReload('/maintenance/due-alerts'),
                ),
              ],
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: CupertinoSearchTextField(
              placeholder: t('maintenance.list.searchHint'),
              style: TextStyle(color: AppColors.text),
              onChanged: onSearch,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: IosFilterBar<String>(
            options: <String?, String>{
              'Scheduled': label(maintenanceStatusLabels, 'Scheduled'),
              'Overdue': t('maintenance.list.overdue'),
              'Completed': label(maintenanceStatusLabels, 'Completed'),
              'Cancelled': label(maintenanceStatusLabels, 'Cancelled'),
            },
            selected: status,
            onSelected: (String? value) => setState(() => status = value ?? 'Scheduled'),
          ),
        ),
        // Lọc theo loại: định kỳ hay sửa chữa
        SliverToBoxAdapter(
          child: IosFilterBar<String>(
            options: <String?, String>{
              null: t('maintenance.list.allKinds'),
              'Periodic': label(maintenanceKindLabels, 'Periodic'),
              'Repair': label(maintenanceKindLabels, 'Repair'),
            },
            selected: kind,
            onSelected: (String? value) => setState(() => kind = value),
          ),
        ),
        IosPagedSliver<MaintenanceRecord>(
          key: listKey,
          query: (status, kind, searchTerm),
          fetchPage: (int pageNumber) => fetchMaintenancePage(
            pageNumber: pageNumber,
            status: isOverdueFilter ? '' : status,
            kind: kind ?? '',
            searchTerm: searchTerm,
            overdueOnly: isOverdueFilter,
            vehicleId: '',
          ),
          emptyText: t('maintenance.list.empty'),
          emptyIcon: CupertinoIcons.wrench,
          footer: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              t('maintenance.list.footer'),
              style: TextStyle(fontSize: 13, height: 1.35, color: IosColors.secondaryLabel),
            ),
          ),
          itemBuilder: (MaintenanceRecord record) => MaintenanceCard(
            record: record,
            onTap: () => openAndReload('/maintenance/${record.publicId}'),
          ),
        ),
      ],
    );
  }
}

/// Thẻ một lịch: tên lịch, biển xe, ngày · loại · chi phí.
/// Lịch quá hạn thì viền đỏ, chữ đỏ, để lướt xuống thấy ngay.
class MaintenanceCard extends StatelessWidget {
  final MaintenanceRecord record;
  final VoidCallback onTap;

  const MaintenanceCard({super.key, required this.record, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bool isOverdue = record.isOverdue && record.status == 'Scheduled';
    final bool isRepair = record.kind == 'Repair';
    final String kindText = label(maintenanceKindLabels, record.kind);
    final Color badgeColor = isOverdue
        ? IosColors.red
        : record.status == 'Completed'
            ? IosColors.green
            : record.status == 'Cancelled'
                ? IosColors.secondaryLabel
                : (isRepair ? IosColors.orange : AppColors.navy);
    return IosCard(
      onTap: onTap,
      borderColor: isOverdue ? IosColors.red.withValues(alpha: 0.45) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          IosIconBadge(icon: isRepair ? CupertinoIcons.hammer_fill : CupertinoIcons.wrench_fill, color: badgeColor, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        record.title,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: isOverdue ? AppColors.errorText : AppColors.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Nhãn góc trên: quá hạn thì ưu tiên hiện quá hạn, không hiện loại
                    isOverdue
                        ? IosPill(t('maintenance.list.overdue'), color: IosColors.red)
                        : IosPill(kindText, color: isRepair ? IosColors.orange : AppColors.navy),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  record.vehicleLabel,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: isOverdue ? AppColors.errorText : AppColors.text),
                ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    Icon(CupertinoIcons.calendar, size: 15, color: AppColors.textMuted),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        '${formatDate(record.startDate)} – ${formatDate(record.endDate)}',
                        style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                      ),
                    ),
                    Text(
                      record.estimatedCost == null ? '--' : formatMoney(record.estimatedCost),
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text),
                    ),
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
