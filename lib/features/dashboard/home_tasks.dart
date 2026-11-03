// "Cần xử lý" trên trang chủ: gộp giấy tờ và đơn đang chờ, việc gấp lên đầu.
import 'dashboard_api.dart';

enum HomeTaskKind { document, finalize, invoice }

class HomeTask {
  final HomeTaskKind kind;
  final VehicleAlert? alert;
  final int count;

  const HomeTask.document(VehicleAlert this.alert)
      : kind = HomeTaskKind.document,
        count = 1;

  const HomeTask.orders(this.kind, this.count) : alert = null;
}

/// Thứ tự: giấy đã hết hạn, giấy sắp hết làm xe không chạy được (còn tối đa 3 ngày),
/// đơn chờ chốt, đơn chờ hóa đơn, rồi các giấy còn lại. Cùng nhóm thì gần hạn hơn đứng trước.
List<HomeTask> homeTasks(DashboardSummary summary) {
  final List<VehicleAlert> alerts = List<VehicleAlert>.of(summary.urgentAlerts)
    ..sort((VehicleAlert a, VehicleAlert b) => a.daysRemaining.compareTo(b.daysRemaining));
  bool urgent(VehicleAlert alert) => alert.daysRemaining < 0 || (alert.blocksCapability != null && alert.daysRemaining <= 3);
  final int finalize = summary.count(summary.orders, 'awaitingFinalizationCount');
  final int invoice = summary.count(summary.orders, 'awaitingInvoiceCount');
  return <HomeTask>[
    for (final VehicleAlert alert in alerts)
      if (urgent(alert)) HomeTask.document(alert),
    if (finalize > 0) HomeTask.orders(HomeTaskKind.finalize, finalize),
    if (invoice > 0) HomeTask.orders(HomeTaskKind.invoice, invoice),
    for (final VehicleAlert alert in alerts)
      if (!urgent(alert)) HomeTask.document(alert),
  ];
}

/// Tỉ lệ xe sẵn sàng từ 0 đến 1 cho vòng quanh avatar. Ưu tiên số server tính sẵn. Không có xe thì null.
double? fleetReadiness(DashboardSummary summary) {
  final int total = summary.count(summary.fleet, 'totalVehicles');
  if (total <= 0) return null;
  // Backend khai số có thể ở dạng chuỗi; đọc được thì dùng, không thì tự tính
  final num? percent = num.tryParse('${summary.fleet['readinessRatePercent']}');
  final double ratio = percent != null ? percent / 100 : summary.count(summary.fleet, 'availableCount') / total;
  return ratio.clamp(0.0, 1.0);
}
