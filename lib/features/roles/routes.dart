// BuildContext (Flutter)
import 'package:flutter/widgets.dart';
// go_router: RouteBase, GoRoute, GoRouterState
import 'package:go_router/go_router.dart';

import 'role_detail_screen.dart';
import 'role_edit_screen.dart';
import 'roles_screen.dart';

// Các màn phân quyền (người 1). router.dart gom vào bằng ...rolesRoutes
final List<RouteBase> rolesRoutes = <RouteBase>[
  // R1: danh sách vai trò
  GoRoute(
    path: '/roles',
    builder: (BuildContext context, GoRouterState state) {
      return const RolesScreen();
    },
  ),
  // R4: tạo vai trò. Phải đứng TRƯỚC /roles/:roleId, nếu không chữ "new" bị hiểu là một roleId
  GoRoute(
    path: '/roles/new',
    builder: (BuildContext context, GoRouterState state) {
      return const RoleEditScreen();
    },
  ),
  // R2: chi tiết vai trò. :roleId là publicId lấy từ đường dẫn
  GoRoute(
    path: '/roles/:roleId',
    builder: (BuildContext context, GoRouterState state) {
      final String roleId = state.pathParameters['roleId']!;
      return RoleDetailScreen(roleId: roleId);
    },
  ),
  // R4: sửa vai trò
  GoRoute(
    path: '/roles/:roleId/edit',
    builder: (BuildContext context, GoRouterState state) {
      final String roleId = state.pathParameters['roleId']!;
      return RoleEditScreen(roleId: roleId);
    },
  ),
];
