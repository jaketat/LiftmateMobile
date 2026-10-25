// Gọi API nhân sự (doc mục 3.4) + cảnh báo giấy tờ người, model và các hộp dữ liệu.
// Riverpod: FutureProvider, Ref
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/call.dart';
import '../../core/api/paged_result.dart';
import '../../core/labels.dart';
import '../fleet/shared.dart';

class StaffUser {
  final String publicId;
  final String fullName;
  final String phone;
  final String? email;
  final String roleName;
  final String? roleId;
  final bool isActive;
  // Bằng lái: chỉ có khi người này là tài xế
  final String? licenseNumber;
  final String? licenseClass;
  final String? licenseExpiryDate;

  StaffUser({
    required this.publicId,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.roleName,
    required this.roleId,
    required this.isActive,
    required this.licenseNumber,
    required this.licenseClass,
    required this.licenseExpiryDate,
  });

  // "Driver" thành "Tài xế"; tên vai trò công ty tự đặt thì giữ nguyên
  String get roleDisplay {
    return label(systemRoleLabels, roleName);
  }

  bool get hasLicense {
    return licenseNumber != null;
  }

  factory StaffUser.fromJson(Map<String, dynamic> data) {
    final Map<String, dynamic>? driver = data['driverProfile'] as Map<String, dynamic>?;
    return StaffUser(
      publicId: data['publicId'] as String,
      fullName: data['fullName'] as String,
      phone: (data['phone'] as String?) ?? '',
      email: data['email'] as String?,
      roleName: data['roleName'] as String,
      roleId: data['roleId'] as String?,
      isActive: data['isActive'] as bool,
      licenseNumber: driver?['licenseNumber'] as String?,
      licenseClass: driver?['licenseClass'] as String?,
      licenseExpiryDate: driver?['licenseExpiryDate'] as String?,
    );
  }
}

// Một giấy tờ người sắp hoặc đã hết hạn (chỉ nhắc, không chặn)
class StaffAlert {
  final String userPublicId;
  final String fullName;
  final String documentType;
  final String effectiveUntil;
  final int daysRemaining;
  final String urgency;

  StaffAlert({
    required this.userPublicId,
    required this.fullName,
    required this.documentType,
    required this.effectiveUntil,
    required this.daysRemaining,
    required this.urgency,
  });

  factory StaffAlert.fromJson(Map<String, dynamic> data) {
    return StaffAlert(
      userPublicId: data['userPublicId'] as String,
      fullName: data['fullName'] as String,
      documentType: data['documentType'] as String,
      effectiveUntil: data['effectiveUntil'] as String,
      daysRemaining: data['daysRemaining'] as int,
      urgency: data['urgency'] as String,
    );
  }
}

// S1: một trang nhân sự. isActive true: đang làm, false: đã khóa.
Future<PagedResult<StaffUser>> fetchStaff(int pageNumber, String search, bool isActive) async {
  final Map<String, dynamic> query = <String, dynamic>{
    'pageNumber': pageNumber,
    'pageSize': 20,
    'isActive': isActive,
  };
  if (search.isNotEmpty) {
    query['searchTerm'] = search;
  }
  return call(
    () {
      return dio.get('/Users', queryParameters: query);
    },
    (dynamic data) {
      return PagedResult<StaffUser>.fromJson(data as Map<String, dynamic>, StaffUser.fromJson);
    },
  );
}

// S2
Future<StaffUser> fetchStaffUser(String userId) async {
  return call(
    () {
      return dio.get('/Users/$userId');
    },
    (dynamic data) {
      return StaffUser.fromJson(data as Map<String, dynamic>);
    },
  );
}

// S2: giấy tờ của người. Xem người khác mà không có Users.ManageComplianceDocs thì server trả 403:
// trả null để màn ẩn cả phần Giấy tờ.
Future<List<ComplianceDoc>?> fetchStaffDocs(String userId) async {
  try {
    return await call(
      () {
        return dio.get('/Users/$userId/compliance-documents');
      },
      parseDocs,
    );
  } on ApiException catch (error) {
    if (error.status == 403) {
      return null;
    }
    rethrow;
  }
}

// Cảnh báo giấy tờ người. urgency: Expired, Urgent, Reminder; null là tất cả.
Future<List<StaffAlert>> fetchStaffAlerts(String? urgency) async {
  return call(
    () {
      return dio.get('/Dashboard/staff-alerts', queryParameters: urgency == null ? null : {'urgency': urgency});
    },
    (dynamic data) {
      final List<StaffAlert> alerts = <StaffAlert>[];
      for (final dynamic row in data as List<dynamic>) {
        alerts.add(StaffAlert.fromJson(row as Map<String, dynamic>));
      }
      return alerts;
    },
  );
}

final staffUserProvider = FutureProvider.autoDispose.family<StaffUser, String>((Ref ref, String userId) {
  return fetchStaffUser(userId);
});

final staffDocsProvider = FutureProvider.autoDispose.family<List<ComplianceDoc>?, String>((Ref ref, String userId) {
  return fetchStaffDocs(userId);
});

final staffAlertsProvider = FutureProvider.autoDispose.family<List<StaffAlert>, String?>((Ref ref, String? urgency) {
  return fetchStaffAlerts(urgency);
});
