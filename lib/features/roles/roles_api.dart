// Gọi API phân quyền (doc mục 3.10) + các model. Màn hình đọc qua roles_providers.dart.
import '../../core/api/api_client.dart';
import '../../core/api/call.dart';
import '../../core/api/paged_result.dart';
import '../../core/labels.dart';

// Một vai trò, vd Giám đốc, Điều phối, hoặc "Thủ kho" công ty tự tạo
class Role {
  final String publicId;
  // Vai trò hệ thống lưu mã tiếng Anh ("CompanyAdmin"), vai trò công ty tạo là tên tiếng Việt
  final String name;
  final String description;
  // true: Giám đốc, Điều phối, Tài xế. Không xóa được.
  final bool isSystemRole;
  final int userCount;
  // Mã quyền, vd ["Orders.View", "Orders.Create"]
  final List<String> permissions;

  Role({
    required this.publicId,
    required this.name,
    required this.description,
    required this.isSystemRole,
    required this.userCount,
    required this.permissions,
  });

  // Tên để hiện: "CompanyAdmin" thành "Giám đốc"; tên công ty tự đặt thì giữ nguyên
  String get displayName {
    return label(systemRoleLabels, name);
  }

  factory Role.fromJson(Map<String, dynamic> data) {
    final List<dynamic> permissionsJson = data['permissions'] as List<dynamic>;
    final List<String> permissions = <String>[];
    for (final dynamic permission in permissionsJson) {
      permissions.add(permission as String);
    }
    return Role(
      publicId: data['publicId'] as String,
      name: data['name'] as String,
      // description có thể null
      description: (data['description'] as String?) ?? '',
      isSystemRole: data['isSystemRole'] as bool,
      userCount: data['userCount'] as int,
      permissions: permissions,
    );
  }
}

// Một quyền trong danh mục: mã + tên tiếng Việt
class PermissionItem {
  final String code;
  final String name;

  PermissionItem({required this.code, required this.name});
}

// Một nhóm quyền, vd "Đơn hàng" gồm Xem đơn, Tạo đơn...
class PermissionGroup {
  final String groupName;
  final List<PermissionItem> permissions;

  PermissionGroup({required this.groupName, required this.permissions});

  factory PermissionGroup.fromJson(Map<String, dynamic> data) {
    final List<dynamic> itemsJson = data['permissions'] as List<dynamic>;
    final List<PermissionItem> permissions = <PermissionItem>[];
    for (final dynamic item in itemsJson) {
      final Map<String, dynamic> itemJson = item as Map<String, dynamic>;
      permissions.add(PermissionItem(
        code: itemJson['code'] as String,
        name: itemJson['name'] as String,
      ));
    }
    return PermissionGroup(groupName: data['groupName'] as String, permissions: permissions);
  }
}

// Một nhân viên trong danh sách "Người giữ vai trò này"
class StaffMember {
  final String publicId;
  final String fullName;
  final String phone;

  StaffMember({required this.publicId, required this.fullName, required this.phone});

  factory StaffMember.fromJson(Map<String, dynamic> data) {
    return StaffMember(
      publicId: data['publicId'] as String,
      fullName: data['fullName'] as String,
      phone: (data['phone'] as String?) ?? '',
    );
  }
}

// R1: mọi vai trò của công ty
Future<List<Role>> fetchRoles() async {
  return call(
    () {
      return dio.get('/Roles');
    },
    (dynamic data) {
      final List<Role> roles = <Role>[];
      for (final dynamic row in data as List<dynamic>) {
        roles.add(Role.fromJson(row as Map<String, dynamic>));
      }
      return roles;
    },
  );
}

// R2: một vai trò
Future<Role> fetchRole(String roleId) async {
  return call(
    () {
      return dio.get('/Roles/$roleId');
    },
    (dynamic data) {
      return Role.fromJson(data as Map<String, dynamic>);
    },
  );
}

// Danh mục quyền có nhóm + tên tiếng Việt, để đổi "Orders.View" thành "Xem đơn hàng"
Future<List<PermissionGroup>> fetchPermissionCatalog() async {
  return call(
    () {
      return dio.get('/Roles/permissions-catalog');
    },
    (dynamic data) {
      final List<PermissionGroup> groups = <PermissionGroup>[];
      for (final dynamic row in data as List<dynamic>) {
        groups.add(PermissionGroup.fromJson(row as Map<String, dynamic>));
      }
      return groups;
    },
  );
}

// R2: nhân viên đang giữ vai trò này.
// ponytail: lấy 1 trang 100 người (server cho tối đa 100); vai trò hơn 100 người thì cần cuộn tải thêm.
Future<List<StaffMember>> fetchUsersByRole(String roleId) async {
  return call(
    () {
      return dio.get('/Users', queryParameters: {'roleId': roleId, 'pageSize': 100});
    },
    (dynamic data) {
      final PagedResult<StaffMember> page = PagedResult<StaffMember>.fromJson(
        data as Map<String, dynamic>,
        StaffMember.fromJson,
      );
      return page.items;
    },
  );
}

// R3: đổi vai trò một nhân viên. Bị chặn (quyền cao hơn mình, hạ giám đốc duy nhất) thì ApiException có message.
Future<void> changeUserRole(String userId, String roleId) async {
  await call(
    () {
      return dio.put('/Users/$userId/role', data: {'roleId': roleId});
    },
    (dynamic data) {
      return null;
    },
  );
}

// R4: tạo vai trò mới. Trùng tên (ROLE_NAME_EXISTS), tick quyền cao hơn mình thì ApiException.
Future<void> createRole(String name, String description, List<String> permissions) async {
  await call(
    () {
      return dio.post('/Roles', data: {
        'name': name,
        'description': description,
        'permissions': permissions,
      });
    },
    (dynamic data) {
      return null;
    },
  );
}

// R4: sửa vai trò. Gửi TOÀN BỘ danh sách quyền mong muốn, không phải phần thay đổi.
// Vai trò hệ thống không đổi được tên (CANNOT_RENAME_SYSTEM_ROLE), nên gửi đúng tên cũ.
Future<void> updateRole(String roleId, String name, String description, List<String> permissions) async {
  await call(
    () {
      return dio.put('/Roles/$roleId', data: {
        'name': name,
        'description': description,
        'permissions': permissions,
      });
    },
    (dynamic data) {
      return null;
    },
  );
}

// R4: xóa vai trò công ty tự tạo, chưa có ai giữ
Future<void> deleteRole(String roleId) async {
  await call(
    () {
      return dio.delete('/Roles/$roleId');
    },
    (dynamic data) {
      return null;
    },
  );
}
