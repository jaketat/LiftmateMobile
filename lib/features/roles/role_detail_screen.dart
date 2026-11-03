// R2: chi tiết vai trò (theo màn N1-ChiTietVaiTro): quyền chia theo nhóm, người đang giữ vai trò.
import 'package:flutter/material.dart';
// Riverpod: ConsumerWidget, WidgetRef, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push, context.pop
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../auth/session_provider.dart';
import 'change_role_sheet.dart';
import 'roles_api.dart';
import 'roles_providers.dart';
import 'roles_screen.dart';
import '../../core/widgets/ios.dart';
import '../../core/widgets/page_transition.dart';

class RoleDetailScreen extends ConsumerWidget {
  final String roleId;

  const RoleDetailScreen({super.key, required this.roleId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Role> roleValue = ref.watch(roleProvider(roleId));

    final Session? session = ref.watch(sessionProvider).value;
    bool canManageRoles = false;
    if (session != null && session.can('Users.ManageRoles')) {
      canManageRoles = true;
    }

    // Tên vai trò lên thanh tiêu đề, nút sửa / xóa khi đã tải xong
    String title = t('roles.detailTitle');
    final List<Widget> actions = <Widget>[];
    if (roleValue.hasValue) {
      final Role role = roleValue.value!;
      title = role.displayName;
      // Không cho sửa Giám đốc trên app: lỡ bỏ tick là giám đốc mất quyền quản lý
      if (canManageRoles && role.name != 'CompanyAdmin') {
        actions.add(
          IconButton(
            tooltip: t('roles.editRole'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: () {
              context.push('/roles/$roleId/edit');
            },
          ),
        );
      }
      // Doc mục 3.10: ẩn nút xóa khi là vai trò hệ thống hoặc còn người giữ
      if (canManageRoles && !role.isSystemRole && role.userCount == 0) {
        actions.add(
          IconButton(
            tooltip: t('roles.delete.tooltip'),
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              confirmDelete(context, ref, role);
            },
          ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: AsyncView<Role>(
        value: roleValue,
        onRetry: () {
          ref.invalidate(roleProvider(roleId));
        },
        builder: (Role role) {
          String summaryKey = 'roles.summary';
          if (role.isSystemRole) {
            summaryKey = 'roles.summarySystem';
          }
          final String summary = t(summaryKey, <String, Object?>{
            'permissions': role.permissions.length,
            'users': role.userCount,
          });

          return ListView(
            padding: withTabBarInset(context, const EdgeInsets.all(16)),
            children: [
              Row(
                children: [
                  RoleKindChip(isSystemRole: role.isSystemRole),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(summary, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                  ),
                ],
              ),
              if (role.description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(role.description, style: TextStyle(fontSize: 14, color: AppColors.label)),
                ),
              DetailSectionTitle(t('roles.permissionsTitle')),
              RolePermissions(role: role),
              DetailSectionTitle(t('roles.holdersTitle')),
              RoleUsers(role: role),
            ],
          );
        },
      ),
    );
  }
}

// Hỏi lại trước khi xóa. showDialog (Flutter): hộp thoại giữa màn, trả về nút người dùng bấm
Future<void> confirmDelete(BuildContext context, WidgetRef ref, Role role) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: Text(t('roles.delete.title')),
        content: Text(t('roles.delete.message', <String, Object?>{'name': role.displayName})),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(false);
            },
            child: Text(t('roles.cancel')),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(true);
            },
            child: Text(t('roles.delete.confirm'), style: TextStyle(color: AppColors.errorText)),
          ),
        ],
      );
    },
  );
  if (confirmed != true || !context.mounted) {
    return;
  }

  try {
    await deleteRole(role.publicId);
    ref.invalidate(rolesProvider);
    if (!context.mounted) {
      return;
    }
    showIosToast(context, t('roles.deleted', <String, Object?>{'name': role.displayName}));
    // Về danh sách vai trò
    context.pop();
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    showErrorSnackBar(context, error);
  }
}

// Quyền của vai trò, chia nhóm, tên tiếng Việt lấy từ danh mục quyền của server (không tự viết)
class RolePermissions extends ConsumerWidget {
  final Role role;

  const RolePermissions({super.key, required this.role});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<PermissionGroup>> catalogValue = ref.watch(permissionCatalogProvider);

    return AsyncView<List<PermissionGroup>>(
      value: catalogValue,
      onRetry: () {
        ref.invalidate(permissionCatalogProvider);
      },
      builder: (List<PermissionGroup> catalog) {
        final List<Widget> groupCards = <Widget>[];
        for (final PermissionGroup group in catalog) {
          // Chỉ lấy các quyền vai trò này có
          final List<Widget> rows = <Widget>[];
          for (final PermissionItem item in group.permissions) {
            if (role.permissions.contains(item.code)) {
              rows.add(
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Icon(Icons.check_box, size: 20, color: AppColors.navy),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(item.name, style: TextStyle(fontSize: 14, color: AppColors.label)),
                      ),
                    ],
                  ),
                ),
              );
            }
          }
          // Nhóm không có quyền nào thì bỏ qua
          if (rows.isEmpty) {
            continue;
          }
          groupCards.add(
            WhiteBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group.groupName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ...rows,
                ],
              ),
            ),
          );
        }

        if (groupCards.isEmpty) {
          return WhiteBox(
            child: Text(
              t('roles.noManagePerms'),
              style: TextStyle(fontSize: 14, color: AppColors.textMuted),
            ),
          );
        }
        return Column(children: groupCards);
      },
    );
  }
}

// Danh sách người đang giữ vai trò, mỗi người có nút "Đổi vai trò" (chỉ người có quyền Users.ManageRoles thấy)
class RoleUsers extends ConsumerWidget {
  final Role role;

  const RoleUsers({super.key, required this.role});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<StaffMember>> usersValue = ref.watch(roleUsersProvider(role.publicId));
    final Session? session = ref.watch(sessionProvider).value;
    bool canManageRoles = false;
    if (session != null && session.can('Users.ManageRoles')) {
      canManageRoles = true;
    }

    return AsyncView<List<StaffMember>>(
      value: usersValue,
      onRetry: () {
        ref.invalidate(roleUsersProvider(role.publicId));
      },
      isEmpty: (List<StaffMember> users) {
        return users.isEmpty;
      },
      emptyText: t('roles.noHolders'),
      builder: (List<StaffMember> users) {
        final List<Widget> rows = <Widget>[];
        for (int index = 0; index < users.length; index++) {
          final StaffMember user = users[index];
          if (index > 0) {
            rows.add(Divider(height: 1, color: AppColors.border));
          }
          Widget? trailing;
          if (canManageRoles) {
            trailing = OutlinedButton(
              onPressed: () {
                showChangeRoleSheet(context, user, role);
              },
              child: Text(t('roles.changeRole')),
            );
          }
          rows.add(
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: AppColors.navyLight,
                child: Text(
                  initialsOf(user.fullName),
                  style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              title: Text(user.fullName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text(user.phone, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
              trailing: trailing,
            ),
          );
        }
        return WhiteBox(child: Column(children: rows));
      },
    );
  }
}

// "Nguyễn Văn An" thành "NA": chữ đầu của từ đầu và từ cuối
String initialsOf(String fullName) {
  final List<String> words = fullName.trim().split(' ');
  String result = '';
  if (words.isNotEmpty && words.first.isNotEmpty) {
    result = words.first[0];
  }
  if (words.length > 1 && words.last.isNotEmpty) {
    result = result + words.last[0];
  }
  return result.toUpperCase();
}

// Tiêu đề nhóm, vd "QUYỀN"
class DetailSectionTitle extends StatelessWidget {
  final String text;

  const DetailSectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: AppColors.textMuted),
      ),
    );
  }
}

// Khung trắng bo góc, viền xám
class WhiteBox extends StatelessWidget {
  final Widget child;

  const WhiteBox({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}
