import 'labels.dart';

class Session {
  // publicId của người đăng nhập: dùng cho "Giấy tờ của tôi" (GET /Users/{id}/compliance-documents)
  final String userId;
  // Có hồ sơ lái xe (tài xế, phụ xe): hiện mục "Chia sẻ vị trí" trong Tài khoản
  final bool hasDriverProfile;
  final String fullName;
  final String companyName;
  // Tên vai trò để hiện, vd "Giám đốc" hoặc tên vai trò công ty tự đặt ("Thủ kho")
  final String roleName;
  // Danh sách quyền, vd ["Orders.View", "Orders.Create"]
  final List<String> permissions;
  // true: bắt đổi mật khẩu trước khi vào app
  final bool mustChangePassword;

  Session({
    this.userId = '',
    this.hasDriverProfile = false,
    required this.fullName,
    required this.companyName,
    required this.roleName,
    required this.permissions,
    required this.mustChangePassword,
  });

  bool can(String permission) {
    return permissions.contains(permission);
  }

  // Đổi phần "data" của GET /auth/me thành Session
  factory Session.fromJson(Map<String, dynamic> data) {
    // "company" là object con
    final Map<String, dynamic> company = data['company'] as Map<String, dynamic>;

    // Tên vai trò được gán. Vai trò hệ thống thì là mã tiếng Anh ("CompanyAdmin"),
    // vai trò công ty tự tạo thì là tên tiếng Việt ("Thủ kho").
    String roleCode = data['role'] as String;
    final String? assignedRoleName = data['customRoleName'] as String?;
    if (assignedRoleName != null) {
      roleCode = assignedRoleName;
    }
    final String roleName = label(systemRoleLabels, roleCode);

    // "permissions" là mảng JSON (List<dynamic>), đổi từng phần tử thành String
    final List<dynamic> permissionsJson = data['permissions'] as List<dynamic>;
    final List<String> permissions = [];
    for (final dynamic permission in permissionsJson) {
      permissions.add(permission as String);
    }

    return Session(
      userId: (data['publicId'] as String?) ?? '',
      hasDriverProfile: data['driverProfile'] != null,
      fullName: data['fullName'] as String,
      companyName: company['companyName'] as String,
      roleName: roleName,
      permissions: permissions,
      mustChangePassword: data['mustChangePassword'] as bool,
    );
  }
}
