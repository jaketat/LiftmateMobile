// R1: danh sách vai trò (theo màn N1-VaiTro trên canvas)
import 'package:flutter/material.dart';
// Riverpod: ConsumerWidget, WidgetRef, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../auth/session_provider.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/page_transition.dart';
import 'roles_api.dart';
import 'roles_providers.dart';

class RolesScreen extends ConsumerWidget {
  const RolesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Role>> rolesValue = ref.watch(rolesProvider);
    final Session? session = ref.watch(sessionProvider).value;

    // Nút + chỉ hiện với người có quyền quản lý vai trò
    final List<Widget> actions = <Widget>[];
    if (session != null && session.can('Users.ManageRoles')) {
      actions.add(
        IconButton(
          tooltip: t('roles.create'),
          icon: const Icon(Icons.add),
          onPressed: () {
            context.push('/roles/new');
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(t('roles.title')), actions: actions),
      // AsyncView (core/widgets): tự vẽ đang tải, lỗi + Thử lại, rỗng, có dữ liệu
      body: AsyncView<List<Role>>(
        value: rolesValue,
        onRetry: () {
          ref.invalidate(rolesProvider);
        },
        isEmpty: (List<Role> roles) {
          return roles.isEmpty;
        },
        emptyText: t('roles.empty'),
        builder: (List<Role> roles) {
          final List<Widget> children = <Widget>[
            Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                t('roles.intro'),
                style: TextStyle(fontSize: 14, color: AppColors.label, height: 1.5),
              ),
            ),
          ];
          for (final Role role in roles) {
            children.add(RoleCard(role: role));
          }
          // RefreshIndicator (Flutter): kéo xuống để tải lại
          return RefreshIndicator(
            onRefresh: () {
              return ref.refresh(rolesProvider.future);
            },
            child: ListView(
              padding: withTabBarInset(context, const EdgeInsets.all(16)),
              children: children,
            ),
          );
        },
      ),
    );
  }
}

// Một thẻ vai trò: tên + nhãn Hệ thống/Công ty tạo, mô tả, số người · số quyền
class RoleCard extends StatelessWidget {
  final Role role;

  const RoleCard({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    String peopleText = t('roles.people', <String, Object?>{'count': role.userCount});
    if (role.userCount == 0) {
      peopleText = t('roles.nobody');
    }

    return Card(
      margin: const EdgeInsets.only(top: 10),
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      // InkWell (Flutter): cả thẻ bấm được, có hiệu ứng gợn sóng
      child: InkWell(
        onTap: () {
          // Chỉ truyền id, màn chi tiết tự gọi API (doc mục 1.5)
          context.push('/roles/${role.publicId}');
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            role.displayName,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        RoleKindChip(isSystemRole: role.isSystemRole),
                      ],
                    ),
                    if (role.description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          role.description,
                          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      t('roles.cardLine', <String, Object?>{'people': peopleText, 'count': role.permissions.length}),
                      style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

// Nhãn nhỏ "Hệ thống" (xanh) hoặc "Công ty tạo" (cam)
class RoleKindChip extends StatelessWidget {
  final bool isSystemRole;

  const RoleKindChip({super.key, required this.isSystemRole});

  @override
  Widget build(BuildContext context) {
    String text = t('roles.kind.company');
    Color background = AppColors.warmBackground;
    Color foreground = AppColors.warmText;
    if (isSystemRole) {
      text = t('roles.kind.system');
      background = AppColors.navyLight;
      foreground = AppColors.navy;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: foreground)),
    );
  }
}
