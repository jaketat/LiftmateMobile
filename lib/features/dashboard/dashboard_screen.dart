// B1: trang chủ quản lý (theo màn N4-TrangChu). Khối tiền ẩn hẳn khi finance = null (vd điều phối).
import 'package:flutter/material.dart';
// Riverpod: ConsumerWidget, WidgetRef, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push, context.go
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/labels.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../auth/session_provider.dart';
import '../fleet/shared.dart';
import 'dashboard_api.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Session? session = ref.watch(sessionProvider).value;

    // Chỉ có quyền tài chính, không có quyền vận hành: không gọi được summary, đưa sang Doanh thu
    if (!userCan(ref, 'Reports.ViewOperations')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Trang chủ')),
        body: Center(
          child: FilledButton(
            onPressed: () {
              context.push('/dashboard/revenue');
            },
            child: const Text('Xem doanh thu'),
          ),
        ),
      );
    }

    final AsyncValue<DashboardSummary> summaryValue = ref.watch(dashboardSummaryProvider);
    return Scaffold(
      body: AsyncView<DashboardSummary>(
        value: summaryValue,
        onRetry: () {
          ref.invalidate(dashboardSummaryProvider);
        },
        builder: (DashboardSummary summary) {
          return RefreshIndicator(
            onRefresh: () {
              return ref.refresh(dashboardSummaryProvider.future);
            },
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                header(context, session),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  child: Column(
                    children: [
                      fleetCard(context, summary),
                      todayCard(summary),
                      ordersCard(context, summary),
                      if (summary.finance != null) financeCard(context, summary.finance!),
                      alertsCard(context, summary.urgentAlerts),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget header(BuildContext context, Session? session) {
    return Container(
      color: AppColors.navy,
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${session?.companyName ?? ''} · ${dateFormat.format(DateTime.now())}',
            style: const TextStyle(fontSize: 13, color: Color(0xFFC7D2E5)),
          ),
          const SizedBox(height: 4),
          Text(
            'Chào ${session?.fullName ?? ''}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ],
      ),
    );
  }

  // Khung thẻ trắng có tiêu đề + nút chữ bên phải
  Widget card({required String title, String? subtitle, String? actionText, VoidCallback? onAction, required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    if (subtitle != null)
                      Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                  ],
                ),
              ),
              if (actionText != null) TextButton(onPressed: onAction, child: Text(actionText)),
            ],
          ),
          const SizedBox(height: 8),
          Padding(padding: const EdgeInsets.only(right: 8), child: child),
        ],
      ),
    );
  }

  // Các ô số xếp lưới 3 cột
  Widget statGrid(List<StatTile> tiles) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = (constraints.maxWidth - 16) / 3;
        final List<Widget> children = <Widget>[];
        for (final StatTile tile in tiles) {
          children.add(SizedBox(width: width, child: tile));
        }
        return Wrap(spacing: 8, runSpacing: 10, children: children);
      },
    );
  }

  Widget fleetCard(BuildContext context, DashboardSummary summary) {
    final Map<String, dynamic> fleet = summary.fleet;
    String subtitle = '${summary.count(fleet, 'totalVehicles')} xe';
    final num? utilization = fleet['utilizationThisMonthPercent'] as num?;
    if (utilization != null) {
      subtitle = '$subtitle · dùng ${formatNumber(utilization.round())}% tháng này';
    }
    return card(
      title: 'Đội xe',
      subtitle: subtitle,
      actionText: 'Xem xe',
      onAction: () {
        context.go('/fleet');
      },
      child: statGrid(<StatTile>[
        StatTile('${summary.count(fleet, 'availableCount')}', 'Sẵn sàng', color: AppColors.okText),
        StatTile('${summary.count(fleet, 'inUseCount')}', 'Đang chạy', color: AppColors.navy),
        StatTile('${summary.count(fleet, 'maintenanceCount')}', 'Bảo dưỡng', color: AppColors.warnText),
        StatTile('${summary.count(fleet, 'suspendedCount')}', 'Đình chỉ', color: AppColors.errorText),
        StatTile('${summary.count(fleet, 'notRoadworthyCount')}', 'Không được chạy', color: AppColors.errorText),
      ]),
    );
  }

  Widget todayCard(DashboardSummary summary) {
    return card(
      title: 'Hôm nay',
      child: statGrid(<StatTile>[
        StatTile('${summary.count(summary.today, 'tripsToday')}', 'Chuyến'),
        StatTile('${summary.count(summary.today, 'vehiclesOnTripNow')}', 'Xe đang chạy'),
        StatTile('${summary.count(summary.today, 'crewWorkingToday')}', 'Người làm'),
      ]),
    );
  }

  Widget ordersCard(BuildContext context, DashboardSummary summary) {
    return card(
      title: 'Đơn hàng',
      actionText: 'Xem đơn',
      onAction: () {
        context.go('/orders');
      },
      child: statGrid(<StatTile>[
        StatTile('${summary.count(summary.orders, 'activeOrdersCount')}', 'Đang chạy'),
        StatTile('${summary.count(summary.orders, 'awaitingFinalizationCount')}', 'Chờ chốt phát sinh'),
        StatTile('${summary.count(summary.orders, 'awaitingInvoiceCount')}', 'Chờ xuất hóa đơn'),
      ]),
    );
  }

  Widget financeCard(BuildContext context, FinanceSummary finance) {
    return card(
      title: 'Tiền tháng ${DateTime.now().month}',
      actionText: 'Doanh thu năm',
      onAction: () {
        context.push('/dashboard/revenue');
      },
      child: Column(
        children: [
          InfoRow('Doanh thu đã chốt', formatMoney(finance.revenueThisMonth)),
          InfoRow('Chờ chốt', formatMoney(finance.awaitingFinalizationAmount)),
          InfoRow('Chờ xuất hóa đơn', formatMoney(finance.awaitingInvoiceAmount)),
          InfoRow('Chi phí bảo dưỡng', formatMoney(finance.maintenanceCostThisMonth)),
        ],
      ),
    );
  }

  Widget alertsCard(BuildContext context, List<VehicleAlert> alerts) {
    Widget body = const Text('Không có giấy tờ nào sắp hết hạn.', style: TextStyle(color: AppColors.textMuted));
    if (alerts.isNotEmpty) {
      final List<Widget> rows = <Widget>[];
      for (final VehicleAlert alert in alerts) {
        String note = '';
        if (alert.blocksCapability != null) {
          note = alert.daysRemaining < 0 ? 'Không chạy được' : 'Sẽ chặn xe';
        }
        rows.add(InkWell(
          onTap: () {
            context.push('/fleet/${alert.vehiclePublicId}');
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                daysPill(alert.daysRemaining),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${alert.plateNumber} · ${label(vehicleDocumentLabels, alert.documentType).toLowerCase()}',
                        style: const TextStyle(fontSize: 14),
                      ),
                      if (note.isNotEmpty)
                        Text(
                          note,
                          style: const TextStyle(fontSize: 12, color: AppColors.errorText, fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ));
      }
      body = Column(children: rows);
    }
    return card(
      title: 'Giấy tờ gấp',
      actionText: 'Xem tất cả',
      onAction: () {
        context.push('/dashboard/alerts');
      },
      child: body,
    );
  }
}
