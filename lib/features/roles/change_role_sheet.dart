// R3: tấm trượt từ dưới lên để đổi vai trò một nhân viên (theo màn N1-DoiVaiTro).
// Luật an toàn (không gán quyền cao hơn mình, còn ít nhất 1 giám đốc) do server kiểm, app chỉ hiện câu lỗi.
import 'package:flutter/material.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import 'roles_api.dart';
import 'roles_providers.dart';

// Mở tấm trượt. showModalBottomSheet (Flutter): tấm che nửa dưới màn, nền phía sau tối đi
void showChangeRoleSheet(BuildContext context, StaffMember user, Role currentRole) {
  showModalBottomSheet<void>(
    context: context,
    // true: tấm cao theo nội dung, danh sách dài thì cuộn được
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext sheetContext) {
      return ChangeRoleSheet(user: user, currentRole: currentRole);
    },
  );
}

class ChangeRoleSheet extends ConsumerStatefulWidget {
  final StaffMember user;
  final Role currentRole;

  const ChangeRoleSheet({super.key, required this.user, required this.currentRole});

  @override
  ConsumerState<ChangeRoleSheet> createState() {
    return _ChangeRoleSheetState();
  }
}

class _ChangeRoleSheetState extends ConsumerState<ChangeRoleSheet> {
  // Vai trò đang chọn, ban đầu là vai trò hiện tại
  late String selectedRoleId = widget.currentRole.publicId;
  bool isSaving = false;
  String? errorText;

  Future<void> save() async {
    setState(() {
      isSaving = true;
      errorText = null;
    });
    try {
      await changeUserRole(widget.user.publicId, selectedRoleId);
      // Số người của các vai trò đã đổi: đổ các hộp liên quan để tải lại
      ref.invalidate(rolesProvider);
      ref.invalidate(roleProvider(widget.currentRole.publicId));
      ref.invalidate(roleUsersProvider(widget.currentRole.publicId));
      ref.invalidate(roleProvider(selectedRoleId));
      ref.invalidate(roleUsersProvider(selectedRoleId));
      if (!mounted) {
        return;
      }
      // Đóng tấm trượt rồi báo thành công
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã đổi vai trò cho ${widget.user.fullName}.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        isSaving = false;
        // Vd "Không gán được vai trò có quyền cao hơn quyền của bạn."
        errorText = errorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Role>> rolesValue = ref.watch(rolesProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: AsyncView<List<Role>>(
          value: rolesValue,
          onRetry: () {
            ref.invalidate(rolesProvider);
          },
          builder: (List<Role> roles) {
            final List<Widget> options = <Widget>[];
            for (final Role role in roles) {
              Widget? currentTag;
              if (role.publicId == widget.currentRole.publicId) {
                currentTag = const Text('Hiện tại', style: TextStyle(fontSize: 12, color: AppColors.textMuted));
              }
              options.add(
                // RadioListTile (Flutter): một dòng có nút tròn để chọn
                RadioListTile<String>(
                  value: role.publicId,
                  title: Text(role.displayName),
                  secondary: currentTag,
                  contentPadding: EdgeInsets.zero,
                ),
              );
            }

            // Chưa chọn vai trò khác thì nút Lưu xám
            bool canSave = !isSaving && selectedRoleId != widget.currentRole.publicId;

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Đổi vai trò', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.user.fullName} · ${widget.user.phone}',
                    style: const TextStyle(fontSize: 14, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Chọn vai trò mới',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.label),
                  ),
                  // RadioGroup (Flutter): giữ lựa chọn chung cho các RadioListTile bên trong
                  RadioGroup<String>(
                    groupValue: selectedRoleId,
                    onChanged: (String? value) {
                      if (value == null || isSaving) {
                        return;
                      }
                      setState(() {
                        selectedRoleId = value;
                        errorText = null;
                      });
                    },
                    child: Column(children: options),
                  ),
                  // Khung đỏ: câu lỗi server trả khi bị chặn
                  if (errorText != null)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.errorBackground,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(errorText!, style: const TextStyle(fontSize: 14, color: AppColors.errorText)),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          child: const Text('Hủy'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: canSave ? save : null,
                          child: Text(isSaving ? 'Đang lưu...' : 'Lưu'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
