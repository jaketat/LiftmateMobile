// S2: chi tiết nhân sự + bằng lái + giấy tờ (theo màn N4-ChiTietNhanSu).
// Phần Giấy tờ ẩn khi xem người khác mà không có Users.ManageComplianceDocs (server trả 403).
import 'package:flutter/material.dart';
// Riverpod: ConsumerWidget, WidgetRef, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/labels.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../fleet/shared.dart';
import '../roles/change_role_sheet.dart';
import '../roles/role_detail_screen.dart';
import '../roles/roles_api.dart';
import 'staff_api.dart';

class StaffDetailScreen extends ConsumerWidget {
  final String userId;

  const StaffDetailScreen({super.key, required this.userId});

  // "Đổi vai trò" dùng tấm trượt của người 1. Đóng tấm thì tải lại người này.
  Future<void> changeRole(BuildContext context, WidgetRef ref, StaffUser user) async {
    try {
      final Role currentRole = await fetchRole(user.roleId!);
      if (!context.mounted) {
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (BuildContext sheetContext) {
          return ChangeRoleSheet(
            user: StaffMember(publicId: user.publicId, fullName: user.fullName, phone: user.phone),
            currentRole: currentRole,
          );
        },
      );
      ref.invalidate(staffUserProvider(userId));
    } catch (error) {
      if (context.mounted) {
        showErrorSnackBar(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<StaffUser> userValue = ref.watch(staffUserProvider(userId));
    final bool canChangeRole = userCan(ref, 'Users.ManageRoles');
    String title = 'Nhân sự';
    if (userValue.value != null) {
      title = userValue.value!.fullName;
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: AsyncView<StaffUser>(
        value: userValue,
        onRetry: () {
          ref.invalidate(staffUserProvider(userId));
        },
        builder: (StaffUser user) {
          final List<String> contact = <String>[];
          if (user.phone.isNotEmpty) {
            contact.add(user.phone);
          }
          if (user.email != null && user.email!.isNotEmpty) {
            contact.add(user.email!);
          }
          return RefreshIndicator(
            onRefresh: () {
              ref.invalidate(staffDocsProvider(userId));
              return ref.refresh(staffUserProvider(userId).future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                WhiteBox(
                  child: Row(
                    children: [
                      InitialsAvatar(user.fullName, size: 56),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user.fullName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            Text(
                              '${user.roleDisplay} · ${user.isActive ? 'đang làm' : 'đã khóa'}',
                              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                            ),
                            if (contact.isNotEmpty)
                              Text(contact.join(' · '), style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    if (user.phone.isNotEmpty)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            callPhone(context, user.phone);
                          },
                          icon: const Icon(Icons.call_outlined, size: 18),
                          label: const Text('Gọi'),
                        ),
                      ),
                    if (user.phone.isNotEmpty && canChangeRole && user.roleId != null) const SizedBox(width: 8),
                    if (canChangeRole && user.roleId != null)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            changeRole(context, ref, user);
                          },
                          child: const Text('Đổi vai trò'),
                        ),
                      ),
                  ],
                ),
                if (user.hasLicense) ...[
                  const DetailSectionTitle('Bằng lái'),
                  WhiteBox(
                    child: Column(
                      children: [
                        InfoRow('Số bằng', user.licenseNumber!),
                        if (user.licenseClass != null) InfoRow('Hạng', user.licenseClass!),
                        if (user.licenseExpiryDate != null) InfoRow('Hết hạn', formatDay(user.licenseExpiryDate)),
                      ],
                    ),
                  ),
                ],
                StaffDocsSection(userId: userId),
              ],
            ),
          );
        },
      ),
    );
  }
}

class StaffDocsSection extends ConsumerWidget {
  final String userId;

  const StaffDocsSection({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ComplianceDoc>?> docsValue = ref.watch(staffDocsProvider(userId));
    Widget body;
    if (docsValue.hasError && !docsValue.isLoading) {
      body = Row(
        children: [
          Expanded(child: Text(errorMessage(docsValue.error!), style: const TextStyle(color: AppColors.errorText))),
          TextButton(
            onPressed: () {
              ref.invalidate(staffDocsProvider(userId));
            },
            child: const Text('Thử lại'),
          ),
        ],
      );
    } else if (!docsValue.hasValue) {
      body = const Center(child: CircularProgressIndicator());
    } else if (docsValue.value == null) {
      // Không có quyền xem giấy tờ người khác: ẩn hẳn
      return const SizedBox.shrink();
    } else if (docsValue.value!.isEmpty) {
      body = const Text('Chưa có giấy tờ nào.', style: TextStyle(color: AppColors.textMuted));
    } else {
      final List<Widget> rows = <Widget>[];
      for (final ComplianceDoc doc in docsValue.value!) {
        if (rows.isNotEmpty) {
          rows.add(const Divider(height: 1, color: AppColors.border));
        }
        // Số căn cước bị che nếu không có quyền: hiện nguyên chuỗi server trả
        String detail = 'Đến ${formatDay(doc.effectiveUntil)} · chỉ nhắc, không chặn điều xe';
        if (doc.documentNumber != null && doc.documentNumber!.isNotEmpty) {
          detail = '${doc.documentNumber} · $detail';
        }
        rows.add(DocTile(doc: doc, typeName: label(personDocumentLabels, doc.documentType), detail: detail));
      }
      body = Column(children: rows);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DetailSectionTitle('Giấy tờ'),
        WhiteBox(child: body),
      ],
    );
  }
}
