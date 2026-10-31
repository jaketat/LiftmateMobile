// Gọi API cho khu tài xế (app tài xế, Người 2): chuyến của tôi, bấm mốc, hoàn tác,
// đồng ý chia sẻ vị trí, gửi vị trí, ảnh và biên bản giao hàng.
// Theo docs/api/slice-d-tracking-integration.md và slice-06-dispatch-integration.md mục 3.5.
// Tài xế không thấy giá tiền, tiền dầu: server không trả các trường đó ở /me/trips.
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/api/call.dart';

// ------------------------------------------------------------------ Đọc số an toàn

// OpenAPI khai số là ['number', 'string']: server có thể trả 3630 hoặc "3630".
double? readDouble(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value.toString());
}

int readInt(dynamic value, [int fallback = 0]) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse('${value ?? ''}') ?? fallback;
}

String readString(dynamic value) {
  if (value == null) {
    return '';
  }
  return value.toString();
}

List<Map<String, dynamic>> readList(dynamic value) {
  final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];
  for (final dynamic row in (value as List<dynamic>?) ?? <dynamic>[]) {
    rows.add(row as Map<String, dynamic>);
  }
  return rows;
}

// ------------------------------------------------------------------ Mô hình

class TripVehicle {
  final String publicId;
  final String plateNumber;
  final String vehicleType;
  // Truck, TractorHead, Trailer, MobileCraneWheeled, MobileCraneCrawler, Forklift
  final String baseType;

  const TripVehicle({
    required this.publicId,
    required this.plateNumber,
    required this.vehicleType,
    required this.baseType,
  });

  // Biển số, xe không có biển (cẩu bánh xích) thì hiện loại xe
  String get displayName => plateNumber.isEmpty ? vehicleType : plateNumber;

  factory TripVehicle.fromJson(Map<String, dynamic> json) {
    return TripVehicle(
      publicId: readString(json['publicId']),
      plateNumber: readString(json['plateNumber']),
      vehicleType: readString(json['vehicleType']),
      baseType: readString(json['baseType']),
    );
  }
}

class TripCrew {
  final String userPublicId;
  final String fullName;
  final String phone;
  // MainDriver, Assistant
  final String role;
  final String? vehiclePublicId;

  const TripCrew({
    required this.userPublicId,
    required this.fullName,
    required this.phone,
    required this.role,
    required this.vehiclePublicId,
  });

  factory TripCrew.fromJson(Map<String, dynamic> json) {
    return TripCrew(
      userPublicId: readString(json['userPublicId']),
      fullName: readString(json['fullName']),
      phone: readString(json['phone']),
      role: readString(json['role']),
      vehiclePublicId: json['vehiclePublicId'] as String?,
    );
  }
}

class TripStop {
  final int sequence;
  // Pickup, Delivery, Via
  final String kind;
  final String address;
  final double? latitude;
  final double? longitude;
  final String? contactName;
  final String? contactPhone;
  final String? note;

  const TripStop({
    required this.sequence,
    required this.kind,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.contactName,
    required this.contactPhone,
    required this.note,
  });

  bool get hasCoordinates => latitude != null && longitude != null;

  factory TripStop.fromJson(Map<String, dynamic> json) {
    return TripStop(
      sequence: readInt(json['sequence']),
      kind: readString(json['kind']),
      address: readString(json['address']),
      latitude: readDouble(json['latitude']),
      longitude: readDouble(json['longitude']),
      contactName: json['contactName'] as String?,
      contactPhone: json['contactPhone'] as String?,
      note: json['note'] as String?,
    );
  }
}

class TripMilestone {
  final String publicId;
  final int stopSequence;
  // Arrived, Loaded, Unloaded, Departed
  final String kind;
  final DateTime recordedAt;
  // Giờ server nhận: đây là giờ hiện cho người dùng (doc mục 2)
  final DateTime receivedAt;
  final bool canUndo;

  const TripMilestone({
    required this.publicId,
    required this.stopSequence,
    required this.kind,
    required this.recordedAt,
    required this.receivedAt,
    required this.canUndo,
  });

  factory TripMilestone.fromJson(Map<String, dynamic> json) {
    return TripMilestone(
      publicId: readString(json['publicId']),
      stopSequence: readInt(json['stopSequence']),
      kind: readString(json['kind']),
      recordedAt: DateTime.parse(json['recordedAt'] as String),
      receivedAt: DateTime.parse(json['receivedAt'] as String),
      canUndo: json['canUndo'] == true,
    );
  }
}

class NextAction {
  final int stopSequence;
  final String kind;

  const NextAction({required this.stopSequence, required this.kind});

  factory NextAction.fromJson(Map<String, dynamic> json) {
    return NextAction(stopSequence: readInt(json['stopSequence']), kind: readString(json['kind']));
  }
}

// Một chuyến của tôi (GET /me/trips, và kết quả của bấm mốc / hoàn tác)
class MyTrip {
  final String publicId;
  final String orderCode;
  final String orderStatus;
  final String customerName;
  final DateTime startAt;
  final DateTime endAt;
  final String? note;
  // MainDriver hoặc Assistant
  final String myRole;
  final String? myVehiclePublicId;
  final List<TripVehicle> vehicles;
  final List<TripCrew> crew;
  final List<TripStop> stops;
  final double? cargoKg;
  final bool canUploadDocuments;
  final List<TripMilestone> milestones;
  // null: chuyến đã xong mọi điểm
  final NextAction? nextAction;
  // false: ngoài khung chuyến (nới 12 giờ hai đầu) hoặc đơn không còn chạy → ẩn nút bấm mốc
  final bool trackingActive;
  // Tuyến xe tải đã lưu của đơn (BR-TRK-011); null thì nối thẳng các điểm
  final String? routePolyline;

  const MyTrip({
    this.routePolyline,
    required this.publicId,
    required this.orderCode,
    required this.orderStatus,
    required this.customerName,
    required this.startAt,
    required this.endAt,
    required this.note,
    required this.myRole,
    required this.myVehiclePublicId,
    required this.vehicles,
    required this.crew,
    required this.stops,
    required this.cargoKg,
    required this.canUploadDocuments,
    required this.milestones,
    required this.nextAction,
    required this.trackingActive,
  });

  bool get isMainDriver => myRole == 'MainDriver';

  TripVehicle? get myVehicle {
    for (final TripVehicle vehicle in vehicles) {
      if (vehicle.publicId == myVehiclePublicId) {
        return vehicle;
      }
    }
    if (vehicles.isNotEmpty) {
      return vehicles.first;
    }
    return null;
  }

  TripStop? stopAt(int sequence) {
    for (final TripStop stop in stops) {
      if (stop.sequence == sequence) {
        return stop;
      }
    }
    return null;
  }

  // Mốc đã bấm ở một điểm, theo thứ tự thời gian
  List<TripMilestone> milestonesAt(int sequence) {
    final List<TripMilestone> result = <TripMilestone>[];
    for (final TripMilestone milestone in milestones) {
      if (milestone.stopSequence == sequence) {
        result.add(milestone);
      }
    }
    result.sort((TripMilestone a, TripMilestone b) => a.receivedAt.compareTo(b.receivedAt));
    return result;
  }

  factory MyTrip.fromJson(Map<String, dynamic> json) {
    final List<TripStop> stops = readList(json['stops']).map(TripStop.fromJson).toList();
    stops.sort((TripStop a, TripStop b) => a.sequence.compareTo(b.sequence));
    final dynamic next = json['nextAction'];
    return MyTrip(
      publicId: readString(json['publicId']),
      orderCode: readString(json['orderCode']),
      orderStatus: readString(json['orderStatus']),
      customerName: readString(json['customerName']),
      startAt: DateTime.parse(json['startAt'] as String),
      endAt: DateTime.parse(json['endAt'] as String),
      note: json['note'] as String?,
      myRole: readString(json['myRole']),
      myVehiclePublicId: json['myVehiclePublicId'] as String?,
      vehicles: readList(json['vehicles']).map(TripVehicle.fromJson).toList(),
      crew: readList(json['crew']).map(TripCrew.fromJson).toList(),
      stops: stops,
      cargoKg: readDouble(json['cargoKg']),
      canUploadDocuments: json['canUploadDocuments'] == true,
      milestones: readList(json['milestones']).map(TripMilestone.fromJson).toList(),
      nextAction: next is Map<String, dynamic> ? NextAction.fromJson(next) : null,
      trackingActive: json['trackingActive'] == true,
      routePolyline: json['routePolyline'] as String?,
    );
  }
}

class LocationConsent {
  final bool accepted;
  final String? termsVersion;
  final String currentTermsVersion;

  const LocationConsent({required this.accepted, required this.termsVersion, required this.currentTermsVersion});

  factory LocationConsent.fromJson(Map<String, dynamic> json) {
    return LocationConsent(
      accepted: json['accepted'] == true,
      termsVersion: json['termsVersion'] as String?,
      currentTermsVersion: readString(json['currentTermsVersion']),
    );
  }
}

class LocationPoint {
  final DateTime recordedAt;
  final double latitude;
  final double longitude;
  final double? accuracyM;
  final double? speedKmh;
  final double? heading;

  const LocationPoint({
    required this.recordedAt,
    required this.latitude,
    required this.longitude,
    this.accuracyM,
    this.speedKmh,
    this.heading,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = <String, dynamic>{
      'recordedAt': recordedAt.toUtc().toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'source': 'Foreground',
    };
    if (accuracyM != null) json['accuracyM'] = accuracyM;
    if (speedKmh != null) json['speedKmh'] = speedKmh;
    if (heading != null) json['heading'] = heading;
    return json;
  }
}

class LocationSendResult {
  final int accepted;
  final int rejected;
  final bool trackingActive;
  final int nextIntervalSeconds;

  const LocationSendResult({
    required this.accepted,
    required this.rejected,
    required this.trackingActive,
    required this.nextIntervalSeconds,
  });

  factory LocationSendResult.fromJson(Map<String, dynamic> json) {
    return LocationSendResult(
      accepted: readInt(json['accepted']),
      rejected: readInt(json['rejected']),
      trackingActive: json['trackingActive'] == true,
      nextIntervalSeconds: readInt(json['nextIntervalSeconds'], 30),
    );
  }
}

// Ảnh hiện trường hoặc biên bản đã gửi cho chuyến (GET /me/trips/{id}/documents)
class TripDocument {
  final String publicId;
  // FieldPhoto hoặc POD
  final String documentType;
  final String documentTypeName;
  final String fileUrl;
  final DateTime takenAt;
  final DateTime receivedAt;
  final bool isVoided;
  final String? voidReason;
  final String uploadedByName;

  const TripDocument({
    required this.publicId,
    required this.documentType,
    required this.documentTypeName,
    required this.fileUrl,
    required this.takenAt,
    required this.receivedAt,
    required this.isVoided,
    required this.voidReason,
    required this.uploadedByName,
  });

  // Dòng danh sách: { document, uploadedByName }
  factory TripDocument.fromRow(Map<String, dynamic> row) {
    return TripDocument.fromDocument(row['document'] as Map<String, dynamic>, readString(row['uploadedByName']));
  }

  factory TripDocument.fromDocument(Map<String, dynamic> json, String uploadedByName) {
    return TripDocument(
      publicId: readString(json['publicId']),
      documentType: readString(json['documentType']),
      documentTypeName: readString(json['documentTypeName']),
      fileUrl: readString(json['fileUrl']),
      takenAt: DateTime.parse(json['takenAt'] as String),
      receivedAt: DateTime.parse(json['receivedAt'] as String),
      isVoided: json['isVoided'] == true,
      voidReason: json['voidReason'] as String?,
      uploadedByName: uploadedByName,
    );
  }
}

// ------------------------------------------------------------------ Gọi API

String serverDate(DateTime day) {
  return '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
}

/// T1: chuyến từ 7 ngày trước đến 30 ngày sau (from/to bắt buộc, cách nhau tối đa 62 ngày).
Future<List<MyTrip>> fetchDriverTrips() {
  final DateTime now = DateTime.now();
  return call(
    () {
      return dio.get('/me/trips', queryParameters: <String, dynamic>{
        'from': serverDate(now.subtract(const Duration(days: 7))),
        'to': serverDate(now.add(const Duration(days: 30))),
      });
    },
    (dynamic data) {
      return readList(data).map(MyTrip.fromJson).toList();
    },
  );
}

/// Một lần bấm mốc. Giữ nguyên [idempotencyKey] và [recordedAt] khi gửi lại sau lúc mất mạng.
class MilestoneRequest {
  final int stopSequence;
  final String kind;
  final String idempotencyKey;
  final DateTime pressedAt;
  final double? latitude;
  final double? longitude;
  final double? accuracyM;
  final int? odometerKm;
  final double? engineHours;
  // true khi đây là lần gửi bù: lúc đó mới gửi recordedAt (doc mục 3)
  final bool isRetry;

  MilestoneRequest({
    required this.stopSequence,
    required this.kind,
    String? idempotencyKey,
    DateTime? pressedAt,
    this.latitude,
    this.longitude,
    this.accuracyM,
    this.odometerKm,
    this.engineHours,
    this.isRetry = false,
  })  : idempotencyKey = idempotencyKey ?? const Uuid().v4(),
        pressedAt = pressedAt ?? DateTime.now();

  MilestoneRequest asRetry() {
    return MilestoneRequest(
      stopSequence: stopSequence,
      kind: kind,
      idempotencyKey: idempotencyKey,
      pressedAt: pressedAt,
      latitude: latitude,
      longitude: longitude,
      accuracyM: accuracyM,
      odometerKm: odometerKm,
      engineHours: engineHours,
      isRetry: true,
    );
  }

  MilestoneRequest withMeters({int? odometerKm, double? engineHours}) {
    return MilestoneRequest(
      stopSequence: stopSequence,
      kind: kind,
      idempotencyKey: const Uuid().v4(),
      pressedAt: pressedAt,
      latitude: latitude,
      longitude: longitude,
      accuracyM: accuracyM,
      odometerKm: odometerKm,
      engineHours: engineHours,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = <String, dynamic>{'stopSequence': stopSequence, 'kind': kind};
    // Tọa độ: gửi đủ cả hai hoặc bỏ cả hai
    if (latitude != null && longitude != null) {
      json['latitude'] = latitude;
      json['longitude'] = longitude;
      if (accuracyM != null) json['accuracyM'] = accuracyM;
    }
    if (isRetry) {
      json['recordedAt'] = pressedAt.toUtc().toIso8601String();
    }
    if (odometerKm != null) json['odometerKm'] = odometerKm;
    if (engineHours != null) json['engineHours'] = engineHours;
    return json;
  }
}

/// T3: bấm mốc. Trả chuyến sau khi cập nhật: vẽ lại bằng dữ liệu này, không cần tải lại.
Future<MyTrip> recordMilestone(String tripId, MilestoneRequest request) {
  return call(
    () {
      return dio.post(
        '/me/trips/$tripId/milestones',
        data: request.toJson(),
        options: Options(headers: <String, dynamic>{'Idempotency-Key': request.idempotencyKey}),
      );
    },
    (dynamic data) => MyTrip.fromJson(data as Map<String, dynamic>),
  );
}

/// T4: hoàn tác mốc bấm nhầm (chỉ khi canUndo).
Future<MyTrip> undoMilestone(String tripId, String milestoneId) {
  return call(
    () => dio.delete('/me/trips/$tripId/milestones/$milestoneId'),
    (dynamic data) => MyTrip.fromJson(data as Map<String, dynamic>),
  );
}

/// T7: đã đồng ý chia sẻ vị trí chưa
Future<LocationConsent> fetchLocationConsent() {
  return call(
    () => dio.get('/me/location-consent'),
    (dynamic data) => LocationConsent.fromJson(data as Map<String, dynamic>),
  );
}

/// T7: đồng ý (kèm bản điều khoản vừa đọc) hoặc rút lại
Future<LocationConsent> saveLocationConsent({required bool accepted, String? termsVersion}) {
  return call(
    () {
      return dio.put('/me/location-consent', data: <String, dynamic>{
        'accepted': accepted,
        if (termsVersion != null) 'termsVersion': termsVersion,
      });
    },
    (dynamic data) => LocationConsent.fromJson(data as Map<String, dynamic>),
  );
}

/// T8: gửi vị trí theo lô (tối đa 100 điểm). Không cần Idempotency-Key.
Future<LocationSendResult> sendTripLocations(String tripId, List<LocationPoint> points) {
  return call(
    () {
      return dio.post('/me/trips/$tripId/locations', data: <String, dynamic>{
        'points': points.map((LocationPoint point) => point.toJson()).toList(),
      });
    },
    (dynamic data) => LocationSendResult.fromJson(data as Map<String, dynamic>),
  );
}

/// Một bước trên tuyến xe tải. Không dùng "sign" của Vietmap (xem directions_logic.dart).
class DirectionStep {
  final String? road;
  final int pointIndex;

  const DirectionStep({required this.road, required this.pointIndex});

  factory DirectionStep.fromJson(Map<String, dynamic> json) {
    final String? street = json['streetName'] as String?;
    final String? text = json['text'] as String?;
    return DirectionStep(
      road: (street ?? '').isNotEmpty ? street : ((text ?? '').isNotEmpty ? text : null),
      pointIndex: readInt(json['pointIndex']),
    );
  }
}

/// Tuyến xe tải từ vị trí xe tới điểm kế (BR-TRK-010)
class TripDirections {
  final int stopSequence;
  final double distanceKm;
  final double durationMinutes;
  final String polyline;
  final List<DirectionStep> steps;

  const TripDirections({
    required this.stopSequence,
    required this.distanceKm,
    required this.durationMinutes,
    required this.polyline,
    required this.steps,
  });

  factory TripDirections.fromJson(Map<String, dynamic> json) {
    return TripDirections(
      stopSequence: readInt(json['stopSequence']),
      distanceKm: readDouble(json['distanceKm']) ?? 0,
      durationMinutes: readDouble(json['durationMinutes']) ?? 0,
      polyline: readString(json['polyline']),
      steps: ((json['steps'] as List<dynamic>?) ?? const <dynamic>[])
          .map((dynamic step) => DirectionStep.fromJson(step as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Tuyến xe tải từ vị trí xe tới điểm kế. Vị trí nằm trong body để không lộ trong log; điểm đến do server quyết.
/// Mỗi lần gọi có thể tốn một lượt Vietmap: chỉ gọi khi xe ở xa tuyến đã lưu hoặc đi lệch.
Future<TripDirections> fetchTripDirections(String tripId, double latitude, double longitude) {
  return call(
    () {
      return dio.post('/me/trips/$tripId/directions', data: <String, dynamic>{
        'latitude': latitude,
        'longitude': longitude,
      });
    },
    (dynamic data) => TripDirections.fromJson(data as Map<String, dynamic>),
  );
}

/// T5: ảnh và biên bản tổ lái đã gửi cho chuyến này, mới nhất trước (gồm cả ảnh văn phòng đã hủy)
Future<List<TripDocument>> fetchTripDocuments(String tripId) {
  return call(
    () => dio.get('/me/trips/$tripId/documents', queryParameters: <String, dynamic>{'includeVoided': true}),
    (dynamic data) => readList(data).map(TripDocument.fromRow).toList(),
  );
}

/// T5: tải một ảnh. [documentType]: FieldPhoto (ảnh hiện trường) hoặc POD (biên bản giao hàng).
Future<TripDocument> uploadTripDocument({
  required String tripId,
  required String filePath,
  required String documentType,
  required DateTime takenAt,
  double? latitude,
  double? longitude,
  void Function(int sent, int total)? onProgress,
}) async {
  final FormData form = FormData();
  form.fields.add(MapEntry<String, String>('documentType', documentType));
  form.fields.add(MapEntry<String, String>('takenAt', takenAt.toUtc().toIso8601String()));
  if (latitude != null && longitude != null) {
    form.fields.add(MapEntry<String, String>('gpsLatitude', latitude.toString()));
    form.fields.add(MapEntry<String, String>('gpsLongitude', longitude.toString()));
  }
  form.files.add(MapEntry<String, MultipartFile>(
    'file',
    await MultipartFile.fromFile(
      filePath,
      filename: '${documentType.toLowerCase()}-${takenAt.millisecondsSinceEpoch}.jpg',
      contentType: DioMediaType('image', 'jpeg'),
    ),
  ));
  return call(
    () => dio.post('/me/trips/$tripId/documents/upload', data: form, onSendProgress: onProgress),
    (dynamic data) => TripDocument.fromDocument(data as Map<String, dynamic>, ''),
  );
}
