// Gọi API cho màn "Điều phối hôm nay" (doc mục 3.12).
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/api/call.dart';
import '../../core/i18n.dart';

// Chữ hiện cho mức tín hiệu của chuyến (tracking.signal)
// Mã lạ thì hiện nguyên mã, không hiện khóa thô
String signalLabel(String? signal) {
  final String key = 'dispatch.signal.$signal';
  return I18n.has(key) ? t(key) : (signal ?? '');
}

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
  // Một dòng mỗi xe: "51C-900.07 · Xe tải 3 chân"
  final List<String> vehicleLines;
  final List<TripCrewMember> crew;
  // Tài xế có đang chia sẻ vị trí không (false: ẩn nút bản đồ)
  final bool sharingLocation;
  // Vị trí cuối; null khi chưa có
  final TripLocation? lastLocation;

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
    required this.vehicleLines,
    required this.crew,
    required this.sharingLocation,
    required this.lastLocation,
  });

  // Lái chính (để hiện tên và nút gọi); null nếu chưa có ai
  TripCrewMember? get mainDriver {
    for (final TripCrewMember member in crew) {
      if (member.role == 'MainDriver') {
        return member;
      }
    }
    return null;
  }

  factory LiveTrip.fromJson(Map<String, dynamic> json) {
    final List<String> plates = <String>[];
    final List<String> vehicleLines = <String>[];
    for (final dynamic vehicle in (json['vehicles'] as List<dynamic>?) ?? <dynamic>[]) {
      final Map<String, dynamic> vehicleJson = vehicle as Map<String, dynamic>;
      final String? plate = vehicleJson['plateNumber'] as String?;
      if (plate != null) {
        plates.add(plate);
        final String? type = vehicleJson['vehicleType'] as String?;
        if (type != null && type.isNotEmpty) {
          vehicleLines.add('$plate · $type');
        } else {
          vehicleLines.add(plate);
        }
      }
    }

    final List<TripCrewMember> crew = <TripCrewMember>[];
    for (final dynamic member in (json['crew'] as List<dynamic>?) ?? <dynamic>[]) {
      crew.add(TripCrewMember.fromJson(member as Map<String, dynamic>));
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
      vehicleLines: vehicleLines,
      crew: crew,
      sharingLocation: (tracking['sharingLocation'] as bool?) ?? true,
      lastLocation: tracking['lastLocation'] == null
          ? null
          : TripLocation.fromJson(tracking['lastLocation'] as Map<String, dynamic>),
    );
  }
}

// Một người trong chuyến
class TripCrewMember {
  final String fullName;
  final String phone;
  // MainDriver (lái chính) hoặc Assistant (phụ xe)
  final String role;

  TripCrewMember({required this.fullName, required this.phone, required this.role});

  factory TripCrewMember.fromJson(Map<String, dynamic> json) {
    return TripCrewMember(
      fullName: (json['fullName'] as String?) ?? '',
      phone: (json['phone'] as String?) ?? '',
      role: (json['role'] as String?) ?? '',
    );
  }
}

// Vị trí cuối tài xế gửi về
class TripLocation {
  final double latitude;
  final double longitude;
  final String? recordedAt;
  // false: sai số trên 200 m, không nên chỉ lên bản đồ
  final bool usable;

  TripLocation({required this.latitude, required this.longitude, required this.recordedAt, required this.usable});

  factory TripLocation.fromJson(Map<String, dynamic> json) {
    return TripLocation(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      recordedAt: json['recordedAt'] as String?,
      usable: (json['usable'] as bool?) ?? false,
    );
  }
}

// Một mốc tài xế đã bấm (Arrived, Loaded, Unloaded, Departed)
class TripMilestone {
  final String kind;
  final String? recordedAt;
  final String byName;

  TripMilestone({required this.kind, required this.recordedAt, required this.byName});

  factory TripMilestone.fromJson(Map<String, dynamic> json) {
    return TripMilestone(
      kind: (json['kind'] as String?) ?? '',
      recordedAt: json['recordedAt'] as String?,
      byName: (json['byName'] as String?) ?? '',
    );
  }
}

// Một điểm dừng của chuyến
class TripStop {
  final int sequence;
  // Pickup (bốc), Delivery (trả), Via (ghé)
  final String kind;
  final String address;
  final String contactName;
  final String contactPhone;
  final List<TripMilestone> milestones;

  TripStop({
    required this.sequence,
    required this.kind,
    required this.address,
    required this.contactName,
    required this.contactPhone,
    required this.milestones,
  });

  // Điểm đã xong: đã rời, hoặc là điểm trả và đã dỡ xong
  bool get isDone {
    for (final TripMilestone milestone in milestones) {
      if (milestone.kind == 'Departed') {
        return true;
      }
      if (kind == 'Delivery' && milestone.kind == 'Unloaded') {
        return true;
      }
    }
    return false;
  }

  factory TripStop.fromJson(Map<String, dynamic> json) {
    final List<TripMilestone> milestones = <TripMilestone>[];
    for (final dynamic row in (json['milestones'] as List<dynamic>?) ?? <dynamic>[]) {
      milestones.add(TripMilestone.fromJson(row as Map<String, dynamic>));
    }
    return TripStop(
      sequence: (json['sequence'] as num?)?.toInt() ?? 0,
      kind: (json['kind'] as String?) ?? '',
      address: (json['address'] as String?) ?? '',
      contactName: (json['contactName'] as String?) ?? '',
      contactPhone: (json['contactPhone'] as String?) ?? '',
      milestones: milestones,
    );
  }
}

// Ba id để mở màn theo dõi: đơn và chuyến chạy (không phải chuyến kế hoạch)
typedef TrackKey = ({String orderId, String tripId});

// Dữ liệu màn K10: tình trạng chuyến + các điểm dừng kèm mốc
class TripTrack {
  final LiveTrip trip;
  final List<TripStop> stops;

  TripTrack({required this.trip, required this.stops});
}

Future<TripTrack> fetchTripTrack(TrackKey key) async {
  return call(
    () {
      return dio.get('/orders/${key.orderId}/dispatch-trips/${key.tripId}/track');
    },
    (dynamic data) {
      final Map<String, dynamic> json = data as Map<String, dynamic>;
      final List<TripStop> stops = <TripStop>[];
      for (final dynamic row in (json['stops'] as List<dynamic>?) ?? <dynamic>[]) {
        stops.add(TripStop.fromJson(row as Map<String, dynamic>));
      }
      return TripTrack(trip: LiveTrip.fromJson(json['trip'] as Map<String, dynamic>), stops: stops);
    },
  );
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

// Ngày theo giờ Việt Nam: "2026-10-20T07:30:00+07:00" → "20/10"
String formatVietnamDay(String? isoText) {
  if (isoText == null || isoText.isEmpty) {
    return '';
  }
  final DateTime vietnamTime = DateTime.parse(isoText).toUtc().add(const Duration(hours: 7));
  return DateFormat('dd/MM').format(vietnamTime);
}
