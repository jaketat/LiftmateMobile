// Gọi API trang chủ, doanh thu, cảnh báo giấy tờ xe (doc mục 3.5), model và các hộp dữ liệu.
// Riverpod: FutureProvider, Ref
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/call.dart';

// Một giấy tờ xe sắp hoặc đã hết hạn
class VehicleAlert {
  final String vehiclePublicId;
  final String plateNumber;
  final String documentType;
  final String effectiveUntil;
  final int daysRemaining;
  final String urgency;
  // Khác null: giấy chặn xe chạy (đăng kiểm). Null: chỉ nhắc.
  final String? blocksCapability;

  VehicleAlert({
    required this.vehiclePublicId,
    required this.plateNumber,
    required this.documentType,
    required this.effectiveUntil,
    required this.daysRemaining,
    required this.urgency,
    required this.blocksCapability,
  });

  factory VehicleAlert.fromJson(Map<String, dynamic> data) {
    return VehicleAlert(
      vehiclePublicId: data['vehiclePublicId'] as String,
      plateNumber: data['plateNumber'] as String,
      documentType: data['documentType'] as String,
      effectiveUntil: data['effectiveUntil'] as String,
      daysRemaining: data['daysRemaining'] as int,
      urgency: data['urgency'] as String,
      blocksCapability: data['blocksCapability'] as String?,
    );
  }
}

List<VehicleAlert> parseVehicleAlerts(dynamic data) {
  final List<VehicleAlert> alerts = <VehicleAlert>[];
  for (final dynamic row in data as List<dynamic>) {
    alerts.add(VehicleAlert.fromJson(row as Map<String, dynamic>));
  }
  return alerts;
}

// Tiền tháng này. Null khi người xem không có Reports.ViewFinance: ẩn cả khối, không hiện "0 đ".
class FinanceSummary {
  final num revenueThisMonth;
  final num awaitingFinalizationAmount;
  final num awaitingInvoiceAmount;
  final num maintenanceCostThisMonth;

  FinanceSummary({
    required this.revenueThisMonth,
    required this.awaitingFinalizationAmount,
    required this.awaitingInvoiceAmount,
    required this.maintenanceCostThisMonth,
  });
}

// B1: mọi con số trang chủ trong 1 lần gọi
class DashboardSummary {
  final Map<String, dynamic> fleet;
  final Map<String, dynamic> today;
  final Map<String, dynamic> orders;
  final FinanceSummary? finance;
  final List<VehicleAlert> urgentAlerts;

  DashboardSummary({
    required this.fleet,
    required this.today,
    required this.orders,
    required this.finance,
    required this.urgentAlerts,
  });

  // Đọc một số đếm, vd count(fleet, 'availableCount')
  int count(Map<String, dynamic> group, String field) {
    return (group[field] as num?)?.toInt() ?? 0;
  }

  factory DashboardSummary.fromJson(Map<String, dynamic> data) {
    final Map<String, dynamic>? financeJson = data['finance'] as Map<String, dynamic>?;
    FinanceSummary? finance;
    if (financeJson != null) {
      finance = FinanceSummary(
        revenueThisMonth: financeJson['revenueThisMonth'] as num,
        awaitingFinalizationAmount: financeJson['awaitingFinalizationAmount'] as num,
        awaitingInvoiceAmount: financeJson['awaitingInvoiceAmount'] as num,
        maintenanceCostThisMonth: financeJson['maintenanceCostThisMonth'] as num,
      );
    }
    return DashboardSummary(
      fleet: data['fleet'] as Map<String, dynamic>,
      today: data['today'] as Map<String, dynamic>,
      orders: data['orders'] as Map<String, dynamic>,
      finance: finance,
      urgentAlerts: parseVehicleAlerts(data['urgentAlerts']),
    );
  }
}

class MonthRevenue {
  final int month;
  final num revenue;
  final int ordersCount;
  final num estimatedFuelAndTollCost;
  final num maintenanceCost;

  MonthRevenue({
    required this.month,
    required this.revenue,
    required this.ordersCount,
    required this.estimatedFuelAndTollCost,
    required this.maintenanceCost,
  });
}

class TopCustomer {
  final String customerName;
  final num totalSpent;
  final int ordersCount;
  final bool isDeleted;

  TopCustomer({required this.customerName, required this.totalSpent, required this.ordersCount, required this.isDeleted});
}

// B2: báo cáo tài chính một năm
class RevenueReport {
  final num totalRevenueYtd;
  final num totalRevenueThisMonth;
  final num averageOrderValue;
  final num maintenanceCostYtd;
  final num? quoteConversionPercent;
  final List<MonthRevenue> months;
  final List<TopCustomer> topCustomers;

  RevenueReport({
    required this.totalRevenueYtd,
    required this.totalRevenueThisMonth,
    required this.averageOrderValue,
    required this.maintenanceCostYtd,
    required this.quoteConversionPercent,
    required this.months,
    required this.topCustomers,
  });

  factory RevenueReport.fromJson(Map<String, dynamic> data) {
    final List<MonthRevenue> months = <MonthRevenue>[];
    for (final dynamic row in data['monthlyRevenue'] as List<dynamic>) {
      final Map<String, dynamic> json = row as Map<String, dynamic>;
      months.add(MonthRevenue(
        month: json['month'] as int,
        revenue: json['revenue'] as num,
        ordersCount: json['ordersCount'] as int,
        estimatedFuelAndTollCost: json['estimatedFuelAndTollCost'] as num,
        maintenanceCost: json['maintenanceCost'] as num,
      ));
    }
    final List<TopCustomer> topCustomers = <TopCustomer>[];
    for (final dynamic row in data['topCustomers'] as List<dynamic>) {
      final Map<String, dynamic> json = row as Map<String, dynamic>;
      topCustomers.add(TopCustomer(
        customerName: json['customerName'] as String,
        totalSpent: json['totalSpent'] as num,
        ordersCount: json['ordersCount'] as int,
        isDeleted: json['isDeleted'] as bool,
      ));
    }
    return RevenueReport(
      totalRevenueYtd: data['totalRevenueYtd'] as num,
      totalRevenueThisMonth: data['totalRevenueThisMonth'] as num,
      averageOrderValue: data['averageOrderValue'] as num,
      maintenanceCostYtd: data['maintenanceCostYtd'] as num,
      quoteConversionPercent: data['quoteConversionPercent'] as num?,
      months: months,
      topCustomers: topCustomers,
    );
  }
}

Future<DashboardSummary> fetchDashboardSummary() async {
  return call(
    () {
      return dio.get('/Dashboard/summary');
    },
    (dynamic data) {
      return DashboardSummary.fromJson(data as Map<String, dynamic>);
    },
  );
}

Future<RevenueReport> fetchRevenue(int year) async {
  return call(
    () {
      return dio.get('/Dashboard/revenue', queryParameters: {'year': year});
    },
    (dynamic data) {
      return RevenueReport.fromJson(data as Map<String, dynamic>);
    },
  );
}

// urgency: Expired, Urgent, Reminder; null là tất cả
Future<List<VehicleAlert>> fetchVehicleAlerts(String? urgency) async {
  return call(
    () {
      return dio.get('/Dashboard/alerts', queryParameters: urgency == null ? null : {'urgency': urgency});
    },
    parseVehicleAlerts,
  );
}

final FutureProvider<DashboardSummary> dashboardSummaryProvider =
    FutureProvider.autoDispose<DashboardSummary>((Ref ref) {
  return fetchDashboardSummary();
});

final revenueProvider = FutureProvider.autoDispose.family<RevenueReport, int>((Ref ref, int year) {
  return fetchRevenue(year);
});

final vehicleAlertsProvider = FutureProvider.autoDispose.family<List<VehicleAlert>, String?>((Ref ref, String? urgency) {
  return fetchVehicleAlerts(urgency);
});
