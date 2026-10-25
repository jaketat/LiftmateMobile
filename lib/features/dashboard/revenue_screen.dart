// B2: doanh thu theo năm: 12 cột tháng (fl_chart), top 5 khách (theo màn N4-DoanhThu)
// fl_chart: BarChart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../roles/role_detail_screen.dart';
import 'dashboard_api.dart';

class RevenueScreen extends ConsumerStatefulWidget {
  const RevenueScreen({super.key});

  @override
  ConsumerState<RevenueScreen> createState() {
    return _RevenueScreenState();
  }
}

class _RevenueScreenState extends ConsumerState<RevenueScreen> {
  int year = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<RevenueReport> reportValue = ref.watch(revenueProvider(year));
    final int thisYear = DateTime.now().year;
    final List<PopupMenuEntry<int>> years = <PopupMenuEntry<int>>[];
    for (int y = thisYear; y > thisYear - 5; y--) {
      years.add(PopupMenuItem<int>(value: y, child: Text('$y')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Doanh thu'),
        actions: [
          // Đổi năm thì hộp dữ liệu đổi theo năm, biểu đồ vẽ lại
          PopupMenuButton<int>(
            tooltip: 'Chọn năm',
            initialValue: year,
            itemBuilder: (BuildContext context) {
              return years;
            },
            onSelected: (int picked) {
              setState(() {
                year = picked;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text('$year', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
        ],
      ),
      body: AsyncView<RevenueReport>(
        value: reportValue,
        onRetry: () {
          ref.invalidate(revenueProvider(year));
        },
        builder: (RevenueReport report) {
          return RefreshIndicator(
            onRefresh: () {
              return ref.refresh(revenueProvider(year).future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                ytdCard(report),
                const SizedBox(height: 10),
                kpiGrid(report, year == thisYear),
                const DetailSectionTitle('Doanh thu từng tháng (triệu đồng)'),
                WhiteBox(child: SizedBox(height: 220, child: chart(report, year == thisYear))),
                const Text(
                  'Chạm cột để xem số đơn, dầu và BOT, bảo dưỡng của tháng đó.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const DetailSectionTitle('5 khách chi nhiều nhất'),
                topCustomers(report),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget ytdCard(RevenueReport report) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Doanh thu từ đầu năm', style: TextStyle(fontSize: 13, color: Color(0xFFC7D2E5))),
          const SizedBox(height: 4),
          Text(
            formatMoney(report.totalRevenueYtd),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 4),
          const Text(
            'Theo ngày chốt đơn, số tiền trên đơn, chưa tách VAT',
            style: TextStyle(fontSize: 12, color: Color(0xFFC7D2E5)),
          ),
        ],
      ),
    );
  }

  Widget kpi(String name, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget kpiGrid(RevenueReport report, bool isThisYear) {
    String conversion = '—';
    if (report.quoteConversionPercent != null) {
      conversion = '${formatNumber(report.quoteConversionPercent!.round())}%';
    }
    final List<Widget> tiles = <Widget>[
      // Năm cũ thì "tháng này" không có nghĩa
      if (isThisYear) kpi('Tháng này', formatMoney(report.totalRevenueThisMonth)),
      kpi('Trung bình mỗi đơn', formatMoney(report.averageOrderValue)),
      kpi('Báo giá thành đơn', conversion),
      kpi('Bảo dưỡng từ đầu năm', formatMoney(report.maintenanceCostYtd)),
    ];
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = (constraints.maxWidth - 10) / 2;
        final List<Widget> children = <Widget>[];
        for (final Widget tile in tiles) {
          children.add(SizedBox(width: width, child: tile));
        }
        return Wrap(spacing: 10, runSpacing: 10, children: children);
      },
    );
  }

  Widget chart(RevenueReport report, bool isThisYear) {
    final int currentMonth = DateTime.now().month;
    final List<BarChartGroupData> groups = <BarChartGroupData>[];
    for (final MonthRevenue point in report.months) {
      // Tháng hiện tại màu cam, các tháng khác xanh navy
      Color color = AppColors.navy;
      if (isThisYear && point.month == currentMonth) {
        color = AppColors.orange;
      }
      groups.add(BarChartGroupData(
        x: point.month,
        barRods: <BarChartRodData>[
          BarChartRodData(
            toY: point.revenue / 1000000,
            color: color,
            width: 14,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      ));
    }

    return BarChart(
      BarChartData(
        barGroups: groups,
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (double value, TitleMeta meta) {
                return Text(formatNumber(value.round()), style: const TextStyle(fontSize: 10, color: AppColors.textMuted));
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (double value, TitleMeta meta) {
                return Text('${value.toInt()}', style: const TextStyle(fontSize: 11, color: AppColors.textMuted));
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (BarChartGroupData group) {
              return AppColors.text;
            },
            getTooltipItem: (BarChartGroupData group, int groupIndex, BarChartRodData rod, int rodIndex) {
              final MonthRevenue point = report.months[groupIndex];
              return BarTooltipItem(
                'Tháng ${point.month}: ${formatMoney(point.revenue)}\n'
                '${point.ordersCount} đơn\n'
                'Dầu, BOT: ${formatMoney(point.estimatedFuelAndTollCost)}\n'
                'Bảo dưỡng: ${formatMoney(point.maintenanceCost)}',
                const TextStyle(color: Colors.white, fontSize: 12),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget topCustomers(RevenueReport report) {
    if (report.topCustomers.isEmpty) {
      return const WhiteBox(child: Text('Chưa có khách nào trong năm này.', style: TextStyle(color: AppColors.textMuted)));
    }
    final List<Widget> rows = <Widget>[];
    for (final TopCustomer customer in report.topCustomers) {
      String name = customer.customerName;
      if (customer.isDeleted) {
        name = '$name (đã xóa)';
      }
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: customer.isDeleted ? AppColors.textMuted : AppColors.text,
                    ),
                  ),
                  Text('${customer.ordersCount} đơn', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
            ),
            Text(formatMoney(customer.totalSpent), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
      ));
    }
    return WhiteBox(child: Column(children: rows));
  }
}
