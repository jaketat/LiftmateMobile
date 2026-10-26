// Gọi API bảo hồng + bảo trì (doc mục 3.2-3.5 của tài liệu Người 5) và các model.
// Màn hình đọc qua maintenance_providers.dart, không gọi thẳng từ đây.
//
// Vài trường server khai báo cho phép nhận cả số lẫn chuỗi (kiểu "number|string"),
// nên đọc qua _soThuc cho an toàn thay vì ép kiểu trực tiếp.
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/api/call.dart';
import '../../core/api/paged_result.dart';

double? _soThuc(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value.toString());
}

int? _soNguyen(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value.toString());
}

String _chuoi(Object? value) {
  return (value as String?) ?? '';
}

List<String> _danhSachChuoi(Object? value) {
  final List<String> result = <String>[];
  for (final dynamic row in (value as List<dynamic>?) ?? <dynamic>[]) {
    result.add(row as String);
  }
  return result;
}

// ---------------------------------------------------------------- Bảo hồng

/// Một lần báo hỏng xe. Mở ra từ nút "Báo hồng xe" trong chi tiết chuyến của người 2.
class BreakdownReport {
  final String publicId;
  final String vehiclePublicId;
  // Biển số đã ghép sẵn, vd "51C-900.01" - không cần ghép tay từ baseType
  final String vehicleLabel;
  final String orderCode;
  final String reportedByName;
  final String reportedAt;
  final String severity;
  final String description;
  final List<String> photoUrls;
  final String status;
  final String acknowledgedAt;
  final String acknowledgedByName;
  final String resolvedAt;
  final String resolvedByName;
  final String resolutionNote;
  final String maintenanceRecordPublicId;

  BreakdownReport({
    required this.publicId,
    required this.vehiclePublicId,
    required this.vehicleLabel,
    required this.orderCode,
    required this.reportedByName,
    required this.reportedAt,
    required this.severity,
    required this.description,
    required this.photoUrls,
    required this.status,
    required this.acknowledgedAt,
    required this.acknowledgedByName,
    required this.resolvedAt,
    required this.resolvedByName,
    required this.resolutionNote,
    required this.maintenanceRecordPublicId,
  });

  factory BreakdownReport.fromJson(Map<String, dynamic> data) {
    return BreakdownReport(
      publicId: data['publicId'] as String,
      vehiclePublicId: data['vehiclePublicId'] as String,
      vehicleLabel: _chuoi(data['vehicleLabel']),
      orderCode: _chuoi(data['orderCode']),
      reportedByName: _chuoi(data['reportedByName']),
      reportedAt: data['reportedAt'] as String,
      severity: data['severity'] as String,
      description: _chuoi(data['description']),
      photoUrls: _danhSachChuoi(data['photoUrls']),
      status: data['status'] as String,
      acknowledgedAt: _chuoi(data['acknowledgedAt']),
      acknowledgedByName: _chuoi(data['acknowledgedByName']),
      resolvedAt: _chuoi(data['resolvedAt']),
      resolvedByName: _chuoi(data['resolvedByName']),
      resolutionNote: _chuoi(data['resolutionNote']),
      maintenanceRecordPublicId: _chuoi(data['maintenanceRecordPublicId']),
    );
  }

  /// Đang ở bước nào trong 3 bước Mới → Đã nhận → Đã xử lý (dùng cho thanh tiến độ)
  int get progressStep {
    if (status == 'Resolved') {
      return 2;
    }
    if (status == 'Acknowledged') {
      return 1;
    }
    return 0;
  }
}

/// Một chuyến đã gán xe trong những ngày bảo trì. Chỉ để cảnh báo, không chặn.
class MaintenanceTripConflict {
  final String tripPublicId;
  final String orderCode;
  final String startAt;
  final String endAt;

  MaintenanceTripConflict({
    required this.tripPublicId,
    required this.orderCode,
    required this.startAt,
    required this.endAt,
  });

  factory MaintenanceTripConflict.fromJson(Map<String, dynamic> data) {
    return MaintenanceTripConflict(
      tripPublicId: data['tripPublicId'] as String,
      orderCode: _chuoi(data['orderCode']),
      startAt: data['startAt'] as String,
      endAt: data['endAt'] as String,
    );
  }
}

// ----------------------------------------------------------------- Bảo trì

/// Một lịch bảo trì. Mỗi lịch giữ đúng 1 xe trong khoảng startDate → endDate.
class MaintenanceRecord {
  final String publicId;
  final String vehiclePublicId;
  final String vehicleLabel;
  final String vehicleBaseType;
  // true: xe đã bị xóa khỏi danh mục. Vẫn hiện lịch, nhưng không mở được màn của xe nữa.
  final bool vehicleDeleted;
  final String kind;
  final String title;
  final String description;
  final String startDate;
  final String endDate;
  final String status;
  final bool isOverdue;
  final double? estimatedCost;
  final String completedOn;
  final double? actualCost;
  final double? engineHoursAtCompletion;
  final int? odometerKmAtCompletion;
  final String cancelReason;
  final String cancelledAt;

  MaintenanceRecord({
    required this.publicId,
    required this.vehiclePublicId,
    required this.vehicleLabel,
    required this.vehicleBaseType,
    required this.vehicleDeleted,
    required this.kind,
    required this.title,
    required this.description,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.isOverdue,
    required this.estimatedCost,
    required this.completedOn,
    required this.actualCost,
    required this.engineHoursAtCompletion,
    required this.odometerKmAtCompletion,
    required this.cancelReason,
    required this.cancelledAt,
  });

  factory MaintenanceRecord.fromJson(Map<String, dynamic> data) {
    return MaintenanceRecord(
      publicId: data['publicId'] as String,
      vehiclePublicId: data['vehiclePublicId'] as String,
      vehicleLabel: _chuoi(data['vehicleLabel']),
      vehicleBaseType: _chuoi(data['vehicleBaseType']),
      vehicleDeleted: (data['vehicleDeleted'] as bool?) ?? false,
      kind: data['kind'] as String,
      title: data['title'] as String,
      description: _chuoi(data['description']),
      startDate: data['startDate'] as String,
      endDate: data['endDate'] as String,
      status: data['status'] as String,
      isOverdue: (data['isOverdue'] as bool?) ?? false,
      estimatedCost: _soThuc(data['estimatedCost']),
      completedOn: _chuoi(data['completedOn']),
      actualCost: _soThuc(data['actualCost']),
      engineHoursAtCompletion: _soThuc(data['engineHoursAtCompletion']),
      odometerKmAtCompletion: _soNguyen(data['odometerKmAtCompletion']),
      cancelReason: _chuoi(data['cancelReason']),
      cancelledAt: _chuoi(data['cancelledAt']),
    );
  }

  /// Lịch còn sửa được thì mới có nút hoàn thành / hủy / sửa
  bool get isScheduled => status == 'Scheduled';
}

/// Lịch vừa lưu kèm danh sách chuyến bị ảnh hưởng. Server chỉ cảnh báo, không chặn.
class MaintenanceWriteResult {
  final MaintenanceRecord record;
  final List<MaintenanceTripConflict> conflictingTrips;

  MaintenanceWriteResult({required this.record, required this.conflictingTrips});

  factory MaintenanceWriteResult.fromJson(Map<String, dynamic> data) {
    final List<MaintenanceTripConflict> conflicts = <MaintenanceTripConflict>[];
    for (final dynamic row in (data['conflictingTrips'] as List<dynamic>?) ?? <dynamic>[]) {
      conflicts.add(MaintenanceTripConflict.fromJson(row as Map<String, dynamic>));
    }
    return MaintenanceWriteResult(
      record: MaintenanceRecord.fromJson(data['record'] as Map<String, dynamic>),
      conflictingTrips: conflicts,
    );
  }
}

// ------------------------------------------------- Đền hạn và định mức

/// Một xe sắp hoặc đã đến hạn bảo trì theo định mức của chính nó.
class MaintenanceDueAlert {
  final String vehiclePublicId;
  final String vehicleLabel;
  final String vehicleBaseType;
  // Căn cứ nhắc: EngineHours (giờ máy), Calendar (tháng), Odometer (km), Schedule (lịch quá hạn chưa làm)
  final String basis;
  // DueSoon (sắp đến, vàng) hoặc Overdue (quá hạn, đỏ)
  final String level;
  // Server đã viết sẵn câu tiếng Việt có sẵn hiện thẳng
  final String message;
  final double currentEngineHours;
  final double? hoursRemaining;
  final int? kmRemaining;
  final String dueDate;
  // Đã có lịch sắp tới thì hiện "Đã lên lịch ngày ...", không hiện nút lập lịch nữa
  final String upcomingScheduledStart;
  final String recordPublicId;

  MaintenanceDueAlert({
    required this.vehiclePublicId,
    required this.vehicleLabel,
    required this.vehicleBaseType,
    required this.basis,
    required this.level,
    required this.message,
    required this.currentEngineHours,
    required this.hoursRemaining,
    required this.kmRemaining,
    required this.dueDate,
    required this.upcomingScheduledStart,
    required this.recordPublicId,
  });

  factory MaintenanceDueAlert.fromJson(Map<String, dynamic> data) {
    return MaintenanceDueAlert(
      vehiclePublicId: data['vehiclePublicId'] as String,
      vehicleLabel: _chuoi(data['vehicleLabel']),
      vehicleBaseType: _chuoi(data['vehicleBaseType']),
      basis: data['basis'] as String,
      level: data['level'] as String,
      message: _chuoi(data['message']),
      currentEngineHours: _soThuc(data['currentEngineHours']) ?? 0,
      hoursRemaining: _soThuc(data['hoursRemaining']),
      kmRemaining: _soNguyen(data['kmRemaining']),
      dueDate: _chuoi(data['dueDate']),
      upcomingScheduledStart: _chuoi(data['upcomingScheduledStart']),
      recordPublicId: _chuoi(data['recordPublicId']),
    );
  }

  bool get isOverdue => level == 'Overdue';
}

/// Định mức bảo trì của đúng một xe. Ô nào null nghĩa là không theo đối tiêu đó.
class VehicleMaintenancePlan {
  final String vehiclePublicId;
  final double? intervalHours;
  final int? intervalMonths;
  final int? intervalKm;
  final double baselineEngineHours;
  final double currentEngineHours;
  final int? currentOdometerKm;

  VehicleMaintenancePlan({
    required this.vehiclePublicId,
    required this.intervalHours,
    required this.intervalMonths,
    required this.intervalKm,
    required this.baselineEngineHours,
    required this.currentEngineHours,
    required this.currentOdometerKm,
  });

  factory VehicleMaintenancePlan.fromJson(Map<String, dynamic> data) {
    return VehicleMaintenancePlan(
      vehiclePublicId: data['vehiclePublicId'] as String,
      intervalHours: _soThuc(data['intervalHours']),
      intervalMonths: _soNguyen(data['intervalMonths']),
      intervalKm: _soNguyen(data['intervalKm']),
      baselineEngineHours: _soThuc(data['baselineEngineHours']) ?? 0,
      currentEngineHours: _soThuc(data['currentEngineHours']) ?? 0,
      currentOdometerKm: _soNguyen(data['currentOdometerKm']),
    );
  }
}

// ------------------------------------------------------------- Báo cáo

/// Chi phí của một xe trong khoảng ngày đang xem báo cáo.
class VehicleMaintenanceCost {
  final String vehiclePublicId;
  final String vehicleLabel;
  final String vehicleBaseType;
  final int serviceCount;
  final double totalCost;

  VehicleMaintenanceCost({
    required this.vehiclePublicId,
    required this.vehicleLabel,
    required this.vehicleBaseType,
    required this.serviceCount,
    required this.totalCost,
  });

  factory VehicleMaintenanceCost.fromJson(Map<String, dynamic> data) {
    return VehicleMaintenanceCost(
      vehiclePublicId: data['vehiclePublicId'] as String,
      vehicleLabel: _chuoi(data['vehicleLabel']),
      vehicleBaseType: _chuoi(data['vehicleBaseType']),
      serviceCount: _soNguyen(data['serviceCount']) ?? 0,
      totalCost: _soThuc(data['totalCost']) ?? 0,
    );
  }
}

/// Báo cáo chi phí bảo trì. Chỉ tính lịch đã hoàn thành, theo ngày làm xong thật.
class MaintenanceCostSummary {
  final String from;
  final String to;
  final int completedCount;
  final double totalCost;
  final double periodicCost;
  final double repairCost;
  final int scheduledCount;
  final int overdueCount;
  // Server trả object {baseType: tiền}, vd {"Truck": 78000000}. Rỗng thì không có xe nào xong việc.
  final Map<String, double> costByVehicleBaseType;
  final List<VehicleMaintenanceCost> topVehicles;

  MaintenanceCostSummary({
    required this.from,
    required this.to,
    required this.completedCount,
    required this.totalCost,
    required this.periodicCost,
    required this.repairCost,
    required this.scheduledCount,
    required this.overdueCount,
    required this.costByVehicleBaseType,
    required this.topVehicles,
  });

  factory MaintenanceCostSummary.fromJson(Map<String, dynamic> data) {
    final Map<String, double> byBaseType = <String, double>{};
    final Object? raw = data['costByVehicleBaseType'];
    if (raw is Map) {
      for (final MapEntry<dynamic, dynamic> entry in raw.entries) {
        byBaseType[entry.key.toString()] = _soThuc(entry.value) ?? 0;
      }
    }
    // Server đảm bảo topVehicles đã sắp tốn nhất, nhưng cứ sắp lại cho chắc khi hiện thanh đồ thị
    final List<VehicleMaintenanceCost> top = <VehicleMaintenanceCost>[];
    for (final dynamic row in (data['topVehicles'] as List<dynamic>?) ?? <dynamic>[]) {
      top.add(VehicleMaintenanceCost.fromJson(row as Map<String, dynamic>));
    }
    top.sort((VehicleMaintenanceCost a, VehicleMaintenanceCost b) {
      return b.totalCost.compareTo(a.totalCost);
    });
    return MaintenanceCostSummary(
      from: _chuoi(data['from']),
      to: _chuoi(data['to']),
      completedCount: _soNguyen(data['completedCount']) ?? 0,
      totalCost: _soThuc(data['totalCost']) ?? 0,
      periodicCost: _soThuc(data['periodicCost']) ?? 0,
      repairCost: _soThuc(data['repairCost']) ?? 0,
      scheduledCount: _soNguyen(data['scheduledCount']) ?? 0,
      overdueCount: _soNguyen(data['overdueCount']) ?? 0,
      costByVehicleBaseType: byBaseType,
      topVehicles: top,
    );
  }
}

// -------------------------------------------------- Xe và chuyến (để chọn)

// Một dòng xe trong ô chọn. Rút gọn từ GET /Vehicles của người 4.
class VehicleOption {
  final String publicId;
  final String plateNumber;
  final String vehicleType;
  final String baseType;
  final String status;

  VehicleOption({
    required this.publicId,
    required this.plateNumber,
    required this.vehicleType,
    required this.baseType,
    required this.status,
  });

  factory VehicleOption.fromJson(Map<String, dynamic> data) {
    return VehicleOption(
      publicId: data['publicId'] as String,
      plateNumber: _chuoi(data['plateNumber']),
      vehicleType: _chuoi(data['vehicleType']),
      baseType: _chuoi(data['baseType']),
      status: _chuoi(data['status']),
    );
  }
}

// Một xe trong chuyến đang chạy. Tài xế chỉ báo được xe có mặt trong chuyến của mình.
class TripVehicleOption {
  final String publicId;
  final String plateNumber;
  final String vehicleType;

  TripVehicleOption({
    required this.publicId,
    required this.plateNumber,
    required this.vehicleType,
  });

  factory TripVehicleOption.fromJson(Map<String, dynamic> data) {
    return TripVehicleOption(
      publicId: data['publicId'] as String,
      plateNumber: _chuoi(data['plateNumber']),
      vehicleType: _chuoi(data['vehicleType']),
    );
  }
}

// Chuyến của tôi, rút gọn: dùng làm tiêu đề màn báo hồng và lấy danh sách xe trong chuyến.
class MyTripBrief {
  final String publicId;
  final String orderCode;
  final String startAt;
  final String endAt;
  // Xe mình đang lái. Báo hồng cho xe này thì ghi chú cho biết là xe của mình.
  final String myVehiclePublicId;
  final List<TripVehicleOption> vehicles;

  MyTripBrief({
    required this.publicId,
    required this.orderCode,
    required this.startAt,
    required this.endAt,
    required this.myVehiclePublicId,
    required this.vehicles,
  });

  factory MyTripBrief.fromJson(Map<String, dynamic> data) {
    final List<TripVehicleOption> vehicles = <TripVehicleOption>[];
    for (final dynamic row in (data['vehicles'] as List<dynamic>?) ?? <dynamic>[]) {
      vehicles.add(TripVehicleOption.fromJson(row as Map<String, dynamic>));
    }
    return MyTripBrief(
      publicId: data['publicId'] as String,
      orderCode: _chuoi(data['orderCode']),
      startAt: data['startAt'] as String,
      endAt: data['endAt'] as String,
      myVehiclePublicId: _chuoi(data['myVehiclePublicId']),
      vehicles: vehicles,
    );
  }
}

// --------------------------------------------------- Tham số truy vấn dùng chung

// Bỏ ô nào null thì không gửi lên: server khai báo từng tham số là optional,
// gửi null có thể bị hiểu thành đang lọc theo giá trị rỗng.
Map<String, dynamic> _query({
  int? pageNumber,
  int? pageSize,
  String? searchTerm,
  String? status,
  String? kind,
  String? vehicleId,
  String? from,
  String? to,
  bool? openOnly,
  bool? overdueOnly,
}) {
  final Map<String, dynamic> params = <String, dynamic>{};
  if (pageNumber != null) params['pageNumber'] = pageNumber;
  if (pageSize != null) params['pageSize'] = pageSize;
  if (searchTerm != null && searchTerm.isNotEmpty) params['searchTerm'] = searchTerm;
  if (status != null && status.isNotEmpty) params['status'] = status;
  if (kind != null && kind.isNotEmpty) params['kind'] = kind;
  if (vehicleId != null && vehicleId.isNotEmpty) params['vehicleId'] = vehicleId;
  if (from != null && from.isNotEmpty) params['from'] = from;
  if (to != null && to.isNotEmpty) params['to'] = to;
  if (openOnly != null) params['openOnly'] = openOnly;
  if (overdueOnly != null) params['overdueOnly'] = overdueOnly;
  return params;
}

// ---------------------------------------------------------------- T6: tài xế

/// T6: 50 báo hồng gần nhất do mình gửi. Không phân trang, server đã giới hạn sẵn.
Future<List<BreakdownReport>> fetchMyBreakdowns() async {
  return call(
    () {
      return dio.get('/me/breakdown-reports');
    },
    (dynamic data) {
      final List<BreakdownReport> reports = <BreakdownReport>[];
      for (final dynamic row in data as List<dynamic>) {
        reports.add(BreakdownReport.fromJson(row as Map<String, dynamic>));
      }
      return reports;
    },
  );
}

/// T6: tài xế báo xe của chuyến đang chạy bị hỏng.
/// Gửi multipart vì có ảnh. Mỗi lần bấm sinh một Idempotency-Key mới;
/// bấm lại cùng một lần thì key khác nên tạo báo mới, nhưng gửi trùng cùng key (mạng lag) thì server không ghaihai lần.
Future<BreakdownReport> reportBreakdown({
  required String tripId,
  required String vehicleId,
  required String severity,
  required String description,
  List<String> photoPaths = const <String>[],
  double? latitude,
  double? longitude,
  // Sinh một lần khi mở màn báo: mạng yếu bấm gửi lại không tạo hai báo (web: useIdempotencyKey)
  String? idempotencyKey,
}) async {
  final String key = idempotencyKey ?? const Uuid().v4();
  final FormData form = FormData();
  form.fields.add(MapEntry<String, String>('vehicleId', vehicleId));
  form.fields.add(MapEntry<String, String>('severity', severity));
  form.fields.add(MapEntry<String, String>('description', description));
  if (latitude != null) {
    form.fields.add(MapEntry<String, String>('gpsLatitude', latitude.toString()));
  }
  if (longitude != null) {
    form.fields.add(MapEntry<String, String>('gpsLongitude', longitude.toString()));
  }
  for (int index = 0; index < photoPaths.length; index++) {
    form.files.add(MapEntry<String, MultipartFile>(
      'photos',
      await MultipartFile.fromFile(
        photoPaths[index],
        filename: 'anh-${index + 1}.jpg',
        contentType: DioMediaType('image', 'jpeg'),
      ),
    ));
  }

  return call(
    () {
      return dio.post(
        '/me/trips/$tripId/breakdown-reports',
        data: form,
        options: Options(headers: <String, dynamic>{'Idempotency-Key': key}),
      );
    },
    (dynamic data) {
      return BreakdownReport.fromJson(data as Map<String, dynamic>);
    },
  );
}

// ------------------------------------------------- Q1: quản lý xử lý bảo hồng

/// Q1: danh sách bảo hồng của cả công ty, mới nhất trước.
Future<PagedResult<BreakdownReport>> fetchBreakdownPage({
  int pageNumber = 1,
  int pageSize = 20,
  String? status,
  bool? openOnly,
  String? vehicleId,
}) async {
  return call(
    () {
      return dio.get(
        '/breakdown-reports',
        queryParameters: _query(
          pageNumber: pageNumber,
          pageSize: pageSize,
          status: status,
          openOnly: openOnly,
          vehicleId: vehicleId,
        ),
      );
    },
    (dynamic data) {
      return PagedResult<BreakdownReport>.fromJson(
        data as Map<String, dynamic>,
        BreakdownReport.fromJson,
      );
    },
  );
}

/// Q1: chi tiết một báo hồng, dùng cho tiến độ và đóng báo.
Future<BreakdownReport> fetchBreakdown(String id) async {
  return call(
    () {
      return dio.get('/breakdown-reports/$id');
    },
    (dynamic data) {
      return BreakdownReport.fromJson(data as Map<String, dynamic>);
    },
  );
}

/// Q1: "Đã nhận" - tài xế biết đã có người lo. Không có body.
/// Q1: so bao con chua dong, de dem tren nut loc "Chua dong".
/// Lay 1 ban ghi thoi, chi de doc totalCount.
Future<int> fetchOpenBreakdownCount() async {
  return call(
    () {
      return dio.get('/breakdown-reports', queryParameters: <String, dynamic>{
        'openOnly': true,
        'pageSize': 1,
      });
    },
    (dynamic data) {
      return _soNguyen((data as Map<String, dynamic>)['totalCount']) ?? 0;
    },
  );
}

Future<void> acknowledgeBreakdown(String id) async {
  await call(
    () {
      return dio.post('/breakdown-reports/$id/acknowledge');
    },
    (dynamic data) {
      return null;
    },
  );
}

/// Q1: "Đóng báo" - đã sửa xong. Có thể kèm lịch sửa chữa chính để nối vào báo cáo chi phí.
Future<void> resolveBreakdown(String id, String note, String? maintenanceRecordId) async {
  await call(
    () {
      return dio.post('/breakdown-reports/$id/resolve', data: <String, dynamic>{
        'note': note,
        'maintenanceRecordId': maintenanceRecordId,
      });
    },
    (dynamic data) {
      return null;
    },
  );
}

// ------------------------------------------------------------- M1, M2, M3

/// M1: danh sách lịch bảo trì, mới nhất trước.
Future<PagedResult<MaintenanceRecord>> fetchMaintenancePage({
  int pageNumber = 1,
  int pageSize = 20,
  String? status,
  String? kind,
  String? vehicleId,
  String? searchTerm,
  String? from,
  String? to,
  bool? overdueOnly,
}) async {
  return call(
    () {
      return dio.get(
        '/Maintenance',
        queryParameters: _query(
          pageNumber: pageNumber,
          pageSize: pageSize,
          status: status,
          kind: kind,
          vehicleId: vehicleId,
          searchTerm: searchTerm,
          from: from,
          to: to,
          overdueOnly: overdueOnly,
        ),
      );
    },
    (dynamic data) {
      return PagedResult<MaintenanceRecord>.fromJson(
        data as Map<String, dynamic>,
        MaintenanceRecord.fromJson,
      );
    },
  );
}

/// M3: chi tiết một lịch.
Future<MaintenanceRecord> fetchMaintenance(String id) async {
  return call(
    () {
      return dio.get('/Maintenance/$id');
    },
    (dynamic data) {
      return MaintenanceRecord.fromJson(data as Map<String, dynamic>);
    },
  );
}

/// M2: lập lịch. Trả kèm conflictingTrips để hiện khung cảnh báo vàng (cảnh báo, không chặn).
Future<MaintenanceWriteResult> createMaintenance({
  required String vehiclePublicId,
  required String kind,
  required String title,
  required String startDate,
  required String endDate,
  double? estimatedCost,
  String? description,
}) async {
  return call(
    () {
      return dio.post('/Maintenance', data: <String, dynamic>{
        'vehiclePublicId': vehiclePublicId,
        'kind': kind,
        'title': title,
        'startDate': startDate,
        'endDate': endDate,
        'estimatedCost': ?estimatedCost,
        if (description != null && description.isNotEmpty) 'description': description,
      });
    },
    (dynamic data) {
      return MaintenanceWriteResult.fromJson(data as Map<String, dynamic>);
    },
  );
}

/// M2: sửa lịch, chỉ khi còn "Đã lên lịch". Cũng trả conflictingTrips theo ngày mới.
Future<MaintenanceWriteResult> updateMaintenance({
  required String id,
  required String kind,
  required String title,
  required String startDate,
  required String endDate,
  double? estimatedCost,
  String? description,
}) async {
  return call(
    () {
      return dio.put('/Maintenance/$id', data: <String, dynamic>{
        'kind': kind,
        'title': title,
        'startDate': startDate,
        'endDate': endDate,
        'estimatedCost': ?estimatedCost,
        if (description != null && description.isNotEmpty) 'description': description,
      });
    },
    (dynamic data) {
      return MaintenanceWriteResult.fromJson(data as Map<String, dynamic>);
    },
  );
}

/// M3: hoàn thành. engineHours bắt buộc với lịch định kỳ của xe có theo dõi giờ máy.
Future<void> completeMaintenance({
  required String id,
  required String completedOn,
  required double actualCost,
  double? engineHours,
  int? odometerKm,
}) async {
  await call(
    () {
      return dio.post('/Maintenance/$id/complete', data: <String, dynamic>{
        'completedOn': completedOn,
        'actualCost': actualCost,
        'engineHoursAtCompletion': ?engineHours,
        'odometerKmAtCompletion': ?odometerKm,
      });
    },
    (dynamic data) {
      return null;
    },
  );
}

/// M3: hủy lịch. Lịch vẫn nằm trong danh sách với trạng thái "Đã hủy".
Future<void> cancelMaintenance(String id, String reason) async {
  await call(
    () {
      return dio.post('/Maintenance/$id/cancel', data: <String, dynamic>{'reason': reason});
    },
    (dynamic data) {
      return null;
    },
  );
}

/// M3: sửa chi phí thật sau khi hoàn thành. Bắt buộc có lý do để lưu nhật ký.
Future<void> correctActualCost(String id, double actualCost, String reason) async {
  await call(
    () {
      return dio.patch(
        '/Maintenance/$id/actual-cost',
        data: <String, dynamic>{'actualCost': actualCost, 'reason': reason},
      );
    },
    (dynamic data) {
      return null;
    },
  );
}

// ------------------------------------------------------------- M4 và M5

/// M4: các xe đang sắp hoặc đã quá hạn, quá hạn nằm trước.
Future<List<MaintenanceDueAlert>> fetchDueAlerts() async {
  return call(
    () {
      return dio.get('/Maintenance/due-alerts');
    },
    (dynamic data) {
      final List<MaintenanceDueAlert> alerts = <MaintenanceDueAlert>[];
      for (final dynamic row in data as List<dynamic>) {
        alerts.add(MaintenanceDueAlert.fromJson(row as Map<String, dynamic>));
      }
      // Quá hạn lên trước: đây là thứ cần xem gấp nhất
      alerts.sort((MaintenanceDueAlert a, MaintenanceDueAlert b) {
        if (a.isOverdue != b.isOverdue) {
          return a.isOverdue ? -1 : 1;
        }
        return 0;
      });
      return alerts;
    },
  );
}

/// M5: định mức của một xe.
Future<VehicleMaintenancePlan> fetchMaintenancePlan(String vehicleId) async {
  return call(
    () {
      return dio.get('/Vehicles/$vehicleId/maintenance-plan');
    },
    (dynamic data) {
      return VehicleMaintenancePlan.fromJson(data as Map<String, dynamic>);
    },
  );
}

/// M5: sửa định mức. Truyền null nghĩa là bỏ đối tiêu đó (xe không theo giờ máy chẳng hạn).
Future<void> setMaintenancePlan({
  required String vehicleId,
  double? intervalHours,
  int? intervalMonths,
  int? intervalKm,
}) async {
  await call(
    () {
      return dio.put('/Vehicles/$vehicleId/maintenance-plan', data: <String, dynamic>{
        'intervalHours': intervalHours,
        'intervalMonths': intervalMonths,
        'intervalKm': intervalKm,
      });
    },
    (dynamic data) {
      return null;
    },
  );
}

// ------------------------------------------------------------------- M6

/// M6: báo cáo chi phí theo khoảng ngày. Khoảng ngày tối đa 2 năm.
Future<MaintenanceCostSummary> fetchCostSummary(String from, String to) async {
  return call(
    () {
      return dio.get('/Maintenance/summary', queryParameters: _query(from: from, to: to));
    },
    (dynamic data) {
      return MaintenanceCostSummary.fromJson(data as Map<String, dynamic>);
    },
  );
}

// -------------------------------------------- Xe và chuyến (dùng để chọn)

/// M2: danh sách xe để lập lịch. Lấy 1 trang 100 xe; công ty có quá 100 xe thì cần tìm.
Future<List<VehicleOption>> fetchVehicles({String? searchTerm}) async {
  return call(
    () {
      return dio.get(
        '/Vehicles',
        queryParameters: <String, dynamic>{
          'pageSize': 100,
          if (searchTerm != null && searchTerm.isNotEmpty) 'searchTerm': searchTerm,
        },
      );
    },
    (dynamic data) {
      final PagedResult<VehicleOption> page = PagedResult<VehicleOption>.fromJson(
        data as Map<String, dynamic>,
        VehicleOption.fromJson,
      );
      return page.items;
    },
  );
}

/// T6: danh sách chuyến của tôi. Dùng làm tiêu đề màn báo hồng và để tài xế chọn chuyến.
/// Server không có API lấy đúng một chuyến của tôi, nên tải về rồi tìm theo publicId.
///
/// QUAN TRONG: endpoint nay BAT BUOC co from/to (thieu la server tra 400 VALIDATION_ERROR),
/// va khoang cach giua from voi to toi da 62 ngay. Doc muc T1: danh sach chuyen tu 7 ngay
/// truoc den 30 ngay sau, chuyen hom nay len dau.
Future<List<MyTripBrief>> fetchMyTrips() async {
  return call(
    () {
      return dio.get('/me/trips', queryParameters: <String, dynamic>{
        'from': _ngayServer(DateTime.now().subtract(const Duration(days: 7))),
        'to': _ngayServer(DateTime.now().add(const Duration(days: 30))),
      });
    },
    (dynamic data) {
      final List<MyTripBrief> result = <MyTripBrief>[];
      for (final dynamic row in data as List<dynamic>) {
        result.add(MyTripBrief.fromJson(row as Map<String, dynamic>));
      }
      return result;
    },
  );
}

/// Ngày theo định dạng server nhận: yyyy-MM-dd (không có giờ).
String _ngayServer(DateTime day) {
  return '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
}

/// Q1: lịch sử sửa chữa của một xe, làm ô chọn "lịch sửa chữa liên quan" khi đóng báo.
Future<List<MaintenanceRecord>> fetchVehicleMaintenance(String vehicleId, {int pageSize = 50}) async {
  return call(
    () {
      return dio.get(
        '/Vehicles/$vehicleId/maintenance',
        queryParameters: <String, dynamic>{'pageSize': pageSize},
      );
    },
    (dynamic data) {
      final PagedResult<MaintenanceRecord> page = PagedResult<MaintenanceRecord>.fromJson(
        data as Map<String, dynamic>,
        MaintenanceRecord.fromJson,
      );
      return page.items;
    },
  );
}