// Các hộp dữ liệu của màn phân quyền. Màn hình ref.watch hộp nào thì hộp đó tự gọi API.
// autoDispose: không còn màn nào nhìn thì bỏ hộp, lần sau mở lại thì gọi API lấy dữ liệu mới.
// family: mỗi id một hộp riêng, vd roleProvider('abc') và roleProvider('xyz').
// Riverpod: FutureProvider, Ref
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'roles_api.dart';

final FutureProvider<List<Role>> rolesProvider = FutureProvider.autoDispose<List<Role>>((Ref ref) {
  return fetchRoles();
});

final roleProvider = FutureProvider.autoDispose.family<Role, String>((Ref ref, String roleId) {
  return fetchRole(roleId);
});

// Danh mục quyền gần như không đổi nên không autoDispose: gọi 1 lần, giữ suốt lúc mở app
final FutureProvider<List<PermissionGroup>> permissionCatalogProvider =
    FutureProvider<List<PermissionGroup>>((Ref ref) {
  return fetchPermissionCatalog();
});

final roleUsersProvider = FutureProvider.autoDispose.family<List<StaffMember>, String>((Ref ref, String roleId) {
  return fetchUsersByRole(roleId);
});
