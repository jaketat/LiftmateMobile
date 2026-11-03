// Gọi API xe + giấy tờ xe (doc mục 3.2, 3.3), model và các hộp dữ liệu (provider).
// Riverpod: FutureProvider, Ref
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/call.dart';
import '../../core/api/paged_result.dart';
import 'shared.dart';

// Một xe trong danh sách
class Vehicle {
  final String publicId;
  final String? plateNumber;
  final String? manufacturerSerialNumber;
  final String baseType;
  // Tên loại xe công ty đặt, vd "Xe tải 3 chân"
  final String vehicleType;
  final String? brand;
  final String? model;
  final int? manufactureYear;
  final num maxPayloadKg;
  final num currentEngineHours;
  final String status;
  final String? inspectionExpiryDate;
  // false: hết đăng kiểm, nhãn đỏ, không gán chuyến được
  final bool isInspectionValid;

  Vehicle({
    required this.publicId,
    required this.plateNumber,
    required this.manufacturerSerialNumber,
    required this.baseType,
    required this.vehicleType,
    required this.brand,
    required this.model,
    required this.manufactureYear,
    required this.maxPayloadKg,
    required this.currentEngineHours,
    required this.status,
    required this.inspectionExpiryDate,
    required this.isInspectionValid,
  });

  // Moóc, xe nâng có thể không có biển số: dùng số khung
  String get title {
    return plateNumber ?? manufacturerSerialNumber ?? vehicleType;
  }

  // "Hino FL"
  String get brandModel {
    final List<String> parts = <String>[];
    if (brand != null && brand!.isNotEmpty) {
      parts.add(brand!);
    }
    if (model != null && model!.isNotEmpty) {
      parts.add(model!);
    }
    return parts.join(' ');
  }

  factory Vehicle.fromJson(Map<String, dynamic> data) {
    return Vehicle(
      publicId: data['publicId'] as String,
      plateNumber: data['plateNumber'] as String?,
      manufacturerSerialNumber: data['manufacturerSerialNumber'] as String?,
      baseType: data['baseType'] as String,
      vehicleType: data['vehicleType'] as String,
      brand: data['brand'] as String?,
      model: data['model'] as String?,
      manufactureYear: data['manufactureYear'] as int?,
      maxPayloadKg: data['maxPayloadKg'] as num,
      currentEngineHours: data['currentEngineHours'] as num,
      status: data['status'] as String,
      inspectionExpiryDate: data['inspectionExpiryDate'] as String?,
      isInspectionValid: data['isInspectionValid'] as bool,
    );
  }
}

// Một lần bảo dưỡng gần đây
class MaintenanceItem {
  final String title;
  final String kind;
  final String status;
  final String startDate;
  final String? completedOn;

  MaintenanceItem({
    required this.title,
    required this.kind,
    required this.status,
    required this.startDate,
    required this.completedOn,
  });

  factory MaintenanceItem.fromJson(Map<String, dynamic> data) {
    return MaintenanceItem(
      title: data['title'] as String,
      kind: data['kind'] as String,
      status: data['status'] as String,
      startDate: data['startDate'] as String,
      completedOn: data['completedOn'] as String?,
    );
  }
}

// Chi tiết xe. Bỏ qua phần cẩu, xe nâng, trục (đợt này không làm cẩu).
class VehicleDetail {
  // Các trường giống danh sách
  final Vehicle summary;
  final String? inspectionCertificateNumber;
  final String? insuranceExpiryDate;
  final num curbWeightKg;
  final int? deckLengthMm;
  final int? deckWidthMm;
  final num? fuelConsumptionPer100Km;
  // Câu cảnh báo thiếu dữ liệu, hiện khung vàng
  final List<String> capacityWarnings;
  final List<MaintenanceItem> recentMaintenance;

  VehicleDetail({
    required this.summary,
    required this.inspectionCertificateNumber,
    required this.insuranceExpiryDate,
    required this.curbWeightKg,
    required this.deckLengthMm,
    required this.deckWidthMm,
    required this.fuelConsumptionPer100Km,
    required this.capacityWarnings,
    required this.recentMaintenance,
  });

  factory VehicleDetail.fromJson(Map<String, dynamic> data) {
    final List<String> warnings = <String>[];
    for (final dynamic row in (data['capacityWarnings'] as List<dynamic>?) ?? <dynamic>[]) {
      warnings.add((row as Map<String, dynamic>)['message'] as String);
    }
    final List<MaintenanceItem> maintenance = <MaintenanceItem>[];
    for (final dynamic row in (data['recentMaintenance'] as List<dynamic>?) ?? <dynamic>[]) {
      maintenance.add(MaintenanceItem.fromJson(row as Map<String, dynamic>));
    }
    return VehicleDetail(
      summary: Vehicle.fromJson(data),
      inspectionCertificateNumber: data['inspectionCertificateNumber'] as String?,
      insuranceExpiryDate: data['insuranceExpiryDate'] as String?,
      curbWeightKg: data['curbWeightKg'] as num,
      deckLengthMm: data['deckLengthMm'] as int?,
      deckWidthMm: data['deckWidthMm'] as int?,
      fuelConsumptionPer100Km: data['fuelConsumptionPer100Km'] as num?,
      capacityWarnings: warnings,
      recentMaintenance: maintenance,
    );
  }
}

// X1: một trang danh sách xe. Ô lọc nào null thì không gửi.
Future<PagedResult<Vehicle>> fetchVehicles(int pageNumber, String search, String? baseType, String? status, {int pageSize = 20}) async {
  final Map<String, dynamic> query = <String, dynamic>{'pageNumber': pageNumber, 'pageSize': pageSize};
  if (search.isNotEmpty) {
    query['searchTerm'] = search;
  }
  if (baseType != null) {
    query['baseType'] = baseType;
  }
  if (status != null) {
    query['status'] = status;
  }
  return call(
    () {
      return dio.get('/Vehicles', queryParameters: query);
    },
    (dynamic data) {
      return PagedResult<Vehicle>.fromJson(data as Map<String, dynamic>, Vehicle.fromJson);
    },
  );
}

// X2
Future<VehicleDetail> fetchVehicle(String vehicleId) async {
  return call(
    () {
      return dio.get('/Vehicles/$vehicleId');
    },
    (dynamic data) {
      return VehicleDetail.fromJson(data as Map<String, dynamic>);
    },
  );
}

// Số km không có trong chi tiết xe: lấy từ định mức bảo trì. Chưa có số km thì null.
Future<int?> fetchOdometerKm(String vehicleId) async {
  return call(
    () {
      return dio.get('/Vehicles/$vehicleId/maintenance-plan');
    },
    (dynamic data) {
      return (data as Map<String, dynamic>)['currentOdometerKm'] as int?;
    },
  );
}

// X3: Available, UnderMaintenance, Suspended (InUse do hệ thống tự đặt)
Future<void> updateVehicleStatus(String vehicleId, String status) async {
  await call(
    () {
      return dio.patch('/Vehicles/$vehicleId/status', data: {'status': status});
    },
    (dynamic data) {},
  );
}

// X5: số km (quản lý sửa được cả khi giảm, server ghi nhật ký)
Future<void> setOdometer(String vehicleId, int odometerKm) async {
  await call(
    () {
      return dio.patch('/Vehicles/$vehicleId/odometer', data: {'odometerKm': odometerKm});
    },
    (dynamic data) {},
  );
}

// X5: giờ máy, chỉ được tăng hoặc giữ nguyên (nhỏ hơn thì server báo lỗi)
Future<void> setEngineHours(String vehicleId, num newEngineHours) async {
  await call(
    () {
      return dio.patch('/Vehicles/$vehicleId/engine-hours', data: {'newEngineHours': newEngineHours});
    },
    (dynamic data) {},
  );
}

// X4: lịch sử giấy tờ, mới nhất trước
Future<List<ComplianceDoc>> fetchVehicleDocs(String vehicleId) async {
  return call(
    () {
      return dio.get('/Vehicles/$vehicleId/compliance-documents');
    },
    parseDocs,
  );
}

// X4: thêm giấy mới hoặc gia hạn (luôn thêm dòng mới)
Future<void> addVehicleDoc(String vehicleId, Map<String, dynamic> body) async {
  await call(
    () {
      return dio.post('/Vehicles/$vehicleId/compliance-documents', data: body);
    },
    (dynamic data) {},
  );
}

// X4: hủy bản nhập sai, bản ghi vẫn còn trong lịch sử
Future<void> voidVehicleDoc(String vehicleId, String documentId, String reason) async {
  await call(
    () {
      return dio.post('/Vehicles/$vehicleId/compliance-documents/$documentId/void', data: {'reason': reason});
    },
    (dynamic data) {},
  );
}

final vehicleProvider = FutureProvider.autoDispose.family<VehicleDetail, String>((Ref ref, String vehicleId) {
  return fetchVehicle(vehicleId);
});

final vehicleOdometerProvider = FutureProvider.autoDispose.family<int?, String>((Ref ref, String vehicleId) {
  return fetchOdometerKm(vehicleId);
});

final vehicleDocsProvider = FutureProvider.autoDispose.family<List<ComplianceDoc>, String>((Ref ref, String vehicleId) {
  return fetchVehicleDocs(vehicleId);
});
