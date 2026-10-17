// R4: tạo hoặc sửa vai trò bằng màn tick quyền (theo màn N1-SuaVaiTro).
// roleId == null: tạo mới. Có roleId: sửa, tick sẵn quyền cũ.
// Luật an toàn (không tick quyền cao hơn quyền của mình, trùng tên) do server kiểm, app hiện câu lỗi.
import 'package:flutter/material.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.pop
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import 'roles_api.dart';
import 'roles_providers.dart';

class RoleEditScreen extends ConsumerStatefulWidget {
  final String? roleId;

  const RoleEditScreen({super.key, this.roleId});

  @override
  ConsumerState<RoleEditScreen> createState() {
    return _RoleEditScreenState();
  }
}

class _RoleEditScreenState extends ConsumerState<RoleEditScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  // Set (Dart): tập các mã quyền đang tick, không trùng lặp
  final Set<String> selectedPermissions = <String>{};
  // Vai trò đang sửa (null khi tạo mới)
  Role? editingRole;
  // Đã điền dữ liệu cũ vào ô chưa (chỉ điền 1 lần, không đè chữ người dùng đang gõ)
  bool isFilled = false;
  bool isSaving = false;
  String? errorText;

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  // Sửa: lần đầu có dữ liệu thì điền tên, mô tả, tick sẵn quyền cũ
  void fillFrom(Role role) {
    if (isFilled) {
      return;
    }
    isFilled = true;
    editingRole = role;
    nameController.text = role.displayName;
    descriptionController.text = role.description;
    selectedPermissions.addAll(role.permissions);
  }

  Future<void> save() async {
    final String description = descriptionController.text.trim();
    String name = nameController.text.trim();
    final Role? role = editingRole;
    // Vai trò hệ thống không đổi được tên: gửi đúng tên gốc ("Dispatcher"), không gửi chữ hiện ("Điều phối")
    if (role != null && role.isSystemRole) {
      name = role.name;
    }
    if (name.isEmpty) {
      setState(() {
        errorText = 'Nhập tên vai trò.';
      });
      return;
    }

    setState(() {
      isSaving = true;
      errorText = null;
    });
    try {
      final List<String> permissions = selectedPermissions.toList();
      if (role == null) {
        await createRole(name, description, permissions);
      } else {
        await updateRole(role.publicId, name, description, permissions);
        ref.invalidate(roleProvider(role.publicId));
      }
      ref.invalidate(rolesProvider);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu vai trò.')),
      );
      context.pop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        isSaving = false;
        errorText = errorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? roleId = widget.roleId;
    String title = 'Tạo vai trò';
    if (roleId != null) {
      title = 'Sửa vai trò';
    }

    Widget body;
    if (roleId == null) {
      body = buildForm();
    } else {
      // Sửa: chờ tải vai trò xong mới vẽ form
      final AsyncValue<Role> roleValue = ref.watch(roleProvider(roleId));
      body = AsyncView<Role>(
        value: roleValue,
        onRetry: () {
          ref.invalidate(roleProvider(roleId));
        },
        builder: (Role role) {
          fillFrom(role);
          return buildForm();
        },
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: body,
    );
  }

  Widget buildForm() {
    final AsyncValue<List<PermissionGroup>> catalogValue = ref.watch(permissionCatalogProvider);
    final Role? role = editingRole;
    // Vai trò hệ thống: khóa ô tên
    bool canEditName = true;
    if (role != null && role.isSystemRole) {
      canEditName = false;
    }

    return AsyncView<List<PermissionGroup>>(
      value: catalogValue,
      onRetry: () {
        ref.invalidate(permissionCatalogProvider);
      },
      builder: (List<PermissionGroup> catalog) {
        final List<Widget> children = <Widget>[
          const FieldLabel('Tên vai trò'),
          TextField(
            controller: nameController,
            enabled: canEditName,
            decoration: const InputDecoration(hintText: 'VD Thủ kho'),
          ),
          if (!canEditName)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Vai trò hệ thống không đổi được tên.',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
            ),
          const SizedBox(height: 16),
          const FieldLabel('Mô tả'),
          TextField(
            controller: descriptionController,
            maxLines: 2,
            decoration: const InputDecoration(hintText: 'VD Xem xe và lịch bảo trì'),
          ),
          const SizedBox(height: 20),
          Text(
            'Quyền (đã chọn ${selectedPermissions.length})',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ];

        // Mỗi nhóm của danh mục là một khối, mỗi quyền một ô tick
        for (final PermissionGroup group in catalog) {
          final List<Widget> rows = <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(group.groupName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ];
          for (final PermissionItem item in group.permissions) {
            rows.add(
              // CheckboxListTile (Flutter): một dòng có ô tick, bấm cả dòng để tick/bỏ tick
              CheckboxListTile(
                value: selectedPermissions.contains(item.code),
                title: Text(item.name, style: const TextStyle(fontSize: 14)),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                onChanged: isSaving
                    ? null
                    : (bool? checked) {
                        setState(() {
                          if (checked == true) {
                            selectedPermissions.add(item.code);
                          } else {
                            selectedPermissions.remove(item.code);
                          }
                        });
                      },
              ),
            );
          }
          children.add(
            Container(
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
            ),
          );
        }

        if (errorText != null) {
          children.add(
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.errorBackground,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(errorText!, style: const TextStyle(fontSize: 14, color: AppColors.errorText)),
            ),
          );
        }
        children.add(const SizedBox(height: 20));
        children.add(
          FilledButton(
            onPressed: isSaving ? null : save,
            child: Text(isSaving ? 'Đang lưu...' : 'Lưu vai trò'),
          ),
        );

        return ListView(
          padding: const EdgeInsets.all(16),
          children: children,
        );
      },
    );
  }
}

// Nhãn nhỏ phía trên ô nhập
class FieldLabel extends StatelessWidget {
  final String text;

  const FieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.label)),
    );
  }
}
