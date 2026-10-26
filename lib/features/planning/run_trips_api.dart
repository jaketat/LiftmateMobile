// Gọi API chuyến chạy: tạo từ kế hoạch, danh sách, gợi ý xe và tài xế, gán, xếp lại, chốt lịch (doc mục 3.6 đến 3.11).
// "Chuyến chạy" (publicId) khác "chuyến kế hoạch" (PlanTrip.id).
import '../../core/api/api_client.dart';
import '../../core/api/call.dart';

// Xe của chuyến chạy
class RunVehicle {
  final String publicId;
  final String plateNumber;
  final String vehicleType;
  // Truck, Trailer, TractorHead...
  final String baseType;
  final num maxPayloadKg;

  RunVehicle({
    required this.publicId,
    required this.plateNumber,
    required this.vehicleType,
    required this.baseType,
    required this.maxPayloadKg,
  });

  // Moóc không có người lái
  bool get needsDriver => baseType != 'Trailer';

  factory RunVehicle.fromJson(Map<String, dynamic> json) {
    return RunVehicle(
      publicId: json['publicId'] as String,
      plateNumber: (json['plateNumber'] as String?) ?? '',
      vehicleType: (json['vehicleType'] as String?) ?? '',
      baseType: (json['baseType'] as String?) ?? '',
      maxPayloadKg: (json['maxPayloadKg'] as num?) ?? 0,
    );
  }
}

// Người trong tổ lái của chuyến chạy
class RunCrew {
  final String userId;
  final String fullName;
  final String phone;
  // MainDriver hoặc Assistant
  final String role;
  final String? vehicleId;

  RunCrew({required this.userId, required this.fullName, required this.phone, required this.role, required this.vehicleId});

  factory RunCrew.fromJson(Map<String, dynamic> json) {
    return RunCrew(
      userId: (json['userPublicId'] as String?) ?? '',
      fullName: (json['fullName'] as String?) ?? '',
      phone: (json['phone'] as String?) ?? '',
      role: (json['role'] as String?) ?? '',
      vehicleId: json['vehiclePublicId'] as String?,
    );
  }
}

// Vấn đề của chuyến hoặc lý do xe, người không hợp lệ
class RunIssue {
  final String code;
  // Error (phải xử lý) hoặc Warning (chỉ nhắc)
  final String severity;
  final String message;

  RunIssue({required this.code, required this.severity, required this.message});

  bool get isError => severity == 'Error';

  factory RunIssue.fromJson(Map<String, dynamic> json) {
    return RunIssue(
      code: (json['code'] as String?) ?? '',
      severity: (json['severity'] as String?) ?? 'Warning',
      message: (json['message'] as String?) ?? '',
    );
  }
}

List<RunIssue> _issues(dynamic value) {
  final List<RunIssue> issues = <RunIssue>[];
  for (final dynamic row in (value as List<dynamic>?) ?? <dynamic>[]) {
    issues.add(RunIssue.fromJson(row as Map<String, dynamic>));
  }
  return issues;
}

class RunTrip {
  // tripId của chuyến chạy
  final String publicId;
  final int plannedTripSequence;
  // Giờ Việt Nam (+07:00)
  final String? startAt;
  final String? endAt;
  final List<RunVehicle> vehicles;
  final List<RunCrew> crew;
  final List<RunIssue> issues;
  final num? estimatedFuelCost;
  // Gửi kèm khi gán xe để server biết mình đang sửa bản nào
  final int revision;

  RunTrip({
    required this.publicId,
    required this.plannedTripSequence,
    required this.startAt,
    required this.endAt,
    required this.vehicles,
    required this.crew,
    required this.issues,
    required this.estimatedFuelCost,
    required this.revision,
  });

  bool get hasError {
    for (final RunIssue issue in issues) {
      if (issue.isError) {
        return true;
      }
    }
    return false;
  }

  bool get hasWarning {
    for (final RunIssue issue in issues) {
      if (!issue.isError) {
        return true;
      }
    }
    return false;
  }

  // Mỗi xe tự chạy phải có một lái chính
  bool get hasMainDriver {
    for (final RunCrew member in crew) {
      if (member.role == 'MainDriver') {
        return true;
      }
    }
    return false;
  }

  // Đủ điều kiện để chốt lịch: có xe, có lái chính, không còn lỗi Error
  bool get isReady {
    return vehicles.isNotEmpty && hasMainDriver && !hasError;
  }

  factory RunTrip.fromJson(Map<String, dynamic> json) {
    final List<RunVehicle> vehicles = <RunVehicle>[];
    for (final dynamic row in (json['vehicles'] as List<dynamic>?) ?? <dynamic>[]) {
      vehicles.add(RunVehicle.fromJson(row as Map<String, dynamic>));
    }
    final List<RunCrew> crew = <RunCrew>[];
    for (final dynamic row in (json['crew'] as List<dynamic>?) ?? <dynamic>[]) {
      crew.add(RunCrew.fromJson(row as Map<String, dynamic>));
    }
    return RunTrip(
      publicId: json['publicId'] as String,
      plannedTripSequence: (json['plannedTripSequence'] as num?)?.toInt() ?? 0,
      startAt: json['startAt'] as String?,
      endAt: json['endAt'] as String?,
      vehicles: vehicles,
      crew: crew,
      issues: _issues(json['issues']),
      estimatedFuelCost: json['estimatedFuelCost'] as num?,
      revision: (json['revision'] as num?)?.toInt() ?? 0,
    );
  }
}

// Một xe trong danh sách gợi ý
class VehicleCandidate {
  final RunVehicle vehicle;
  // false: không gán được, hiện mờ kèm lý do
  final bool isEligible;
  // true: đúng xe kế hoạch đề xuất
  final bool matchesPlan;
  final List<RunIssue> issues;

  VehicleCandidate({required this.vehicle, required this.isEligible, required this.matchesPlan, required this.issues});

  factory VehicleCandidate.fromJson(Map<String, dynamic> json) {
    return VehicleCandidate(
      vehicle: RunVehicle.fromJson(json['vehicle'] as Map<String, dynamic>),
      isEligible: (json['isEligible'] as bool?) ?? false,
      matchesPlan: (json['matchesPlan'] as bool?) ?? false,
      issues: _issues(json['issues']),
    );
  }
}

// Một người trong danh sách gợi ý
class StaffCandidate {
  final String userId;
  final String fullName;
  final String phone;
  // true: có thể làm lái chính
  final bool isDriver;
  final bool isEligible;
  final List<RunIssue> issues;

  StaffCandidate({
    required this.userId,
    required this.fullName,
    required this.phone,
    required this.isDriver,
    required this.isEligible,
    required this.issues,
  });

  factory StaffCandidate.fromJson(Map<String, dynamic> json) {
    return StaffCandidate(
      userId: json['userPublicId'] as String,
      fullName: (json['fullName'] as String?) ?? '',
      phone: (json['phone'] as String?) ?? '',
      isDriver: (json['isDriver'] as bool?) ?? false,
      isEligible: (json['isEligible'] as bool?) ?? true,
      issues: _issues(json['issues']),
    );
  }
}

class Candidates {
  final RunTrip trip;
  final List<VehicleCandidate> vehicles;
  final List<StaffCandidate> staff;

  Candidates({required this.trip, required this.vehicles, required this.staff});
}

// Kết quả tạo chuyến chạy từ kế hoạch
class CreateRunTripsResult {
  final int createdCount;
  final int skippedCount;
  // Chuyến tạo được nhưng xe không qua luật: "Chuyến 3: lý do"
  final List<String> notAssigned;

  CreateRunTripsResult({required this.createdCount, required this.skippedCount, required this.notAssigned});
}

Future<List<RunTrip>> fetchRunTrips(String orderId) async {
  return call(
    () {
      return dio.get('/orders/$orderId/dispatch-trips');
    },
    (dynamic data) {
      final List<RunTrip> trips = <RunTrip>[];
      for (final dynamic row in data as List<dynamic>) {
        trips.add(RunTrip.fromJson(row as Map<String, dynamic>));
      }
      return trips;
    },
  );
}

// Tạo chuyến chạy từ kế hoạch đã duyệt. Bấm lại không tạo trùng
Future<CreateRunTripsResult> createRunTripsFromPlan(String orderId) async {
  return call(
    () {
      // plannedTripIds rỗng: tạo mọi chuyến chưa tạo
      return dio.post('/orders/$orderId/dispatch-trips/from-plan', data: {'plannedTripIds': <String>[]});
    },
    (dynamic data) {
      final Map<String, dynamic> json = data as Map<String, dynamic>;
      final List<String> notAssigned = <String>[];
      for (final dynamic row in (json['vehicleNotAssigned'] as List<dynamic>?) ?? <dynamic>[]) {
        final Map<String, dynamic> item = row as Map<String, dynamic>;
        notAssigned.add('Chuyến ${item['sequence']}: ${item['reason'] ?? 'chưa gán được xe'}');
      }
      return CreateRunTripsResult(
        createdCount: ((json['created'] as List<dynamic>?) ?? <dynamic>[]).length,
        skippedCount: ((json['skipped'] as List<dynamic>?) ?? <dynamic>[]).length,
        notAssigned: notAssigned,
      );
    },
  );
}

// Chốt lịch. Đơn có cảnh báo quá khổ thì phải gửi acknowledgeOversize = true
Future<void> scheduleOrder(String orderId, {required bool acknowledgeOversize}) async {
  await call(
    () {
      return dio.post('/Orders/$orderId/schedule', data: {'acknowledgeOversize': acknowledgeOversize});
    },
    (dynamic data) {
      return null;
    },
  );
}

Future<Candidates> fetchCandidates(String tripId) async {
  return call(
    () {
      return dio.get('/Dispatch/trips/$tripId/candidates');
    },
    (dynamic data) {
      final Map<String, dynamic> json = data as Map<String, dynamic>;
      final List<VehicleCandidate> vehicles = <VehicleCandidate>[];
      for (final dynamic row in (json['vehicles'] as List<dynamic>?) ?? <dynamic>[]) {
        vehicles.add(VehicleCandidate.fromJson(row as Map<String, dynamic>));
      }
      final List<StaffCandidate> staff = <StaffCandidate>[];
      for (final dynamic row in (json['staff'] as List<dynamic>?) ?? <dynamic>[]) {
        staff.add(StaffCandidate.fromJson(row as Map<String, dynamic>));
      }
      return Candidates(
        trip: RunTrip.fromJson(json['trip'] as Map<String, dynamic>),
        vehicles: vehicles,
        staff: staff,
      );
    },
  );
}

// Một người trong phân công gửi lên
typedef CrewAssignment = ({String userId, String role, String? vehicleId});

// Gửi toàn bộ phân công mong muốn (không phải thêm từng cái)
Future<void> assignRunTrip(
  String orderId,
  String tripId, {
  required List<String> vehicleIds,
  required List<CrewAssignment> crew,
  required int revision,
}) async {
  final List<Map<String, dynamic>> crewJson = <Map<String, dynamic>>[];
  for (final CrewAssignment member in crew) {
    final Map<String, dynamic> row = <String, dynamic>{'userId': member.userId, 'role': member.role};
    if (member.vehicleId != null) {
      row['vehicleId'] = member.vehicleId;
    }
    crewJson.add(row);
  }
  await call(
    () {
      return dio.put(
        '/orders/$orderId/dispatch-trips/$tripId/assignment',
        data: {'vehicleIds': vehicleIds, 'crew': crewJson, 'revision': revision},
      );
    },
    (dynamic data) {
      return null;
    },
  );
}

// Sau lỗi VEHICLE_LAYOUT_UNSAFE: xếp lại hàng của chuyến trên xe đã chọn. Không vừa thì server trả 422 kèm câu giải thích
Future<void> replanForVehicle(String orderId, String tripId, String carrierVehicleId, String? tractorVehicleId) async {
  final Map<String, dynamic> body = <String, dynamic>{'carrierVehicleId': carrierVehicleId};
  if (tractorVehicleId != null) {
    body['tractorVehicleId'] = tractorVehicleId;
  }
  await call(
    () {
      return dio.post('/orders/$orderId/dispatch-trips/$tripId/replan-for-vehicle', data: body);
    },
    (dynamic data) {
      return null;
    },
  );
}
