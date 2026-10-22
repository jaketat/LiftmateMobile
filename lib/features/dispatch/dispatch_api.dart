// Gọi API cho màn "Điều phối hôm nay" (doc mục 3.12).
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/api/call.dart';

// Chữ hiện cho mức tín hiệu của chuyến (tracking.signal)
const Map<String, String> signalLabels = {
  'NotStarted': 'Chưa xuất phát',
  'Live': 'Đang chạy',
  'Slow': 'Chậm',
  'Lost': 'Mất tín hiệu',
  'Finished': 'Đã xong',
};

// Giờ trong ngày theo giờ Việt Nam: "2026-10-16T09:41:00+07:00" → "09:41".
// DateTime.parse luôn đổi về UTC, nên cộng 7 giờ để hiện đúng giờ Việt Nam dù điện thoại đặt múi giờ nào
String formatVietnamClock(String? isoText) {
  if (isoText == null || isoText.isEmpty) {
    return '';
  }
  final DateTime vietnamTime = DateTime.parse(isoText).toUtc().add(const Duration(hours: 7));
  return DateFormat('HH:mm').format(vietnamTime);
}

// Một việc "Cần xử lý" (GET /Dispatch/issues)
class DispatchIssue {
  final String code;
  // Error (viền đỏ) hoặc Warning (viền vàng)
  final String severity;
  // Câu tiếng Việt server viết sẵn, hiện thẳng
  final String message;
  final String? orderId;
  final String orderCode;
  final String? date;
  // null: việc này chưa gắn với chuyến nào, bấm thì mở danh sách chuyến chạy của đơn
  final String? tripId;

  DispatchIssue({
    required this.code,
    required this.severity,
    required this.message,
    required this.orderId,
    required this.orderCode,
    required this.date,
    required this.tripId,
  });

  bool get isError => severity == 'Error';

  factory DispatchIssue.fromJson(Map<String, dynamic> json) {
    return DispatchIssue(
      code: (json['code'] as String?) ?? '',
      severity: (json['severity'] as String?) ?? 'Warning',
      message: (json['message'] as String?) ?? '',
      orderId: json['orderPublicId'] as String?,
      orderCode: (json['orderCode'] as String?) ?? '',
      date: json['date'] as String?,
      tripId: json['tripPublicId'] as String?,
    );
  }
}

// Một chuyến trong ngày (GET /Dispatch/live)
class LiveTrip {
  final String tripId;
  final String orderId;
  final String orderCode;
  final String customerName;
  final String? startAt;
  final List<String> plateNumbers;
  // NotStarted, Live, Slow, Lost, Finished
  final String signal;
  final String? lastUpdateAt;
  final String? etaArriveAt;
  final bool etaApproximate;
  final int delayMinutes;
  final bool isLate;
  final bool hasOpenBreakdown;
  final bool hasMustStopBreakdown;

  LiveTrip({
    required this.tripId,
    required this.orderId,
    required this.orderCode,
    required this.customerName,
    required this.startAt,
    required this.plateNumbers,
    required this.signal,
    required this.lastUpdateAt,
    required this.etaArriveAt,
    required this.etaApproximate,
    required this.delayMinutes,
    required this.isLate,
    required this.hasOpenBreakdown,
    required this.hasMustStopBreakdown,
  });

  factory LiveTrip.fromJson(Map<String, dynamic> json) {
    final List<String> plates = <String>[];
    for (final dynamic vehicle in (json['vehicles'] as List<dynamic>?) ?? <dynamic>[]) {
      final String? plate = (vehicle as Map<String, dynamic>)['plateNumber'] as String?;
      if (plate != null) {
        plates.add(plate);
      }
    }

    // tracking có thể thiếu hoặc rỗng: chuyến chưa xuất phát
    final Map<String, dynamic> tracking = (json['tracking'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final Map<String, dynamic>? eta = tracking['eta'] as Map<String, dynamic>?;

    return LiveTrip(
      tripId: json['tripPublicId'] as String,
      orderId: json['orderPublicId'] as String,
      orderCode: (json['orderCode'] as String?) ?? '',
      customerName: (json['customerName'] as String?) ?? '',
      startAt: json['startAt'] as String?,
      plateNumbers: plates,
      signal: (tracking['signal'] as String?) ?? 'NotStarted',
      lastUpdateAt: tracking['lastUpdateAt'] as String?,
      etaArriveAt: eta?['arriveAt'] as String?,
      etaApproximate: (eta?['approximate'] as bool?) ?? false,
      delayMinutes: (tracking['delayMinutes'] as num?)?.toInt() ?? 0,
      isLate: (tracking['isLate'] as bool?) ?? false,
      hasOpenBreakdown: (tracking['hasOpenBreakdown'] as bool?) ?? false,
      hasMustStopBreakdown: (tracking['hasMustStopBreakdown'] as bool?) ?? false,
    );
  }
}

// Ngày hôm nay dạng "2026-10-16" để gửi lên server
String todayText() {
  return DateFormat('yyyy-MM-dd').format(DateTime.now());
}

Future<List<DispatchIssue>> fetchDispatchIssues() async {
  final String today = todayText();
  return call(
    () {
      // from và to đều là hôm nay
      return dio.get('/Dispatch/issues', queryParameters: {'from': today, 'to': today});
    },
    (dynamic data) {
      final List<DispatchIssue> issues = <DispatchIssue>[];
      for (final dynamic row in data as List<dynamic>) {
        issues.add(DispatchIssue.fromJson(row as Map<String, dynamic>));
      }
      return issues;
    },
  );
}

Future<List<LiveTrip>> fetchLiveTrips() async {
  return call(
    () {
      // Không gửi date: server hiểu là hôm nay
      return dio.get('/Dispatch/live');
    },
    (dynamic data) {
      final List<LiveTrip> trips = <LiveTrip>[];
      for (final dynamic row in data as List<dynamic>) {
        trips.add(LiveTrip.fromJson(row as Map<String, dynamic>));
      }
      return trips;
    },
  );
}
