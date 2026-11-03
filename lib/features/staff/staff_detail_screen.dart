// S2: chi tiết nhân sự + bằng lái + giấy tờ (theo màn N4-ChiTietNhanSu).
// Phần Giấy tờ ẩn khi xem người khác mà không có Users.ManageComplianceDocs (server trả 403).
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
// Riverpod: ConsumerWidget, WidgetRef, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/labels.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/page_transition.dart';
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
        useRootNavigator: true,
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
    String title = t('staff.title');
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
              padding: withTabBarInset(context, const EdgeInsets.fromLTRB(16, 8, 16, 32)),
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
                              t(user.isActive ? 'staff.roleActive' : 'staff.roleLocked', <String, Object?>{'role': user.roleDisplay}),
                              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                            ),
                            if (contact.isNotEmpty)
                              Text(contact.join(' · '), style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
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
                          label: Text(t('common.call')),
                        ),
                      ),
                    if (user.phone.isNotEmpty && canChangeRole && user.roleId != null) const SizedBox(width: 8),
                    if (canChangeRole && user.roleId != null)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            changeRole(context, ref, user);
                          },
                          child: Text(t('staff.changeRole')),
                        ),
                      ),
                  ],
                ),
                if (user.hasLicense) ...[
                  DetailSectionTitle(t('staff.license')),
                  WhiteBox(
                    child: Column(
                      children: [
                        InfoRow(t('staff.licenseNumber'), user.licenseNumber!),
                        if (user.licenseClass != null) InfoRow(t('staff.licenseClass'), user.licenseClass!),
                        if (user.licenseExpiryDate != null) InfoRow(t('staff.licenseExpiry'), formatDay(user.licenseExpiryDate)),
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
          Expanded(child: Text(errorMessage(docsValue.error!), style: TextStyle(color: AppColors.errorText))),
          TextButton(
            onPressed: () {
              ref.invalidate(staffDocsProvider(userId));
            },
            child: Text(t('common.retry')),
          ),
        ],
      );
    } else if (!docsValue.hasValue) {
      body = const Center(child: CupertinoActivityIndicator(radius: 14));
    } else if (docsValue.value == null) {
      // Không có quyền xem giấy tờ người khác: ẩn hẳn
      return const SizedBox.shrink();
    } else if (docsValue.value!.isEmpty) {
      body = Text(t('fleet.noDocs'), style: TextStyle(color: AppColors.textMuted));
    } else {
      final List<Widget> rows = <Widget>[];
      for (final ComplianceDoc doc in docsValue.value!) {
        if (rows.isNotEmpty) {
          rows.add(Divider(height: 1, color: AppColors.border));
        }
        // Số căn cước bị che nếu không có quyền: hiện nguyên chuỗi server trả
        String detail = t('staff.docDetail', <String, Object?>{'date': formatDay(doc.effectiveUntil)});
        if (doc.documentNumber != null && doc.documentNumber!.isNotEmpty) {
          detail = t('staff.docDetailNumber', <String, Object?>{'number': doc.documentNumber, 'date': formatDay(doc.effectiveUntil)});
        }
        rows.add(DocTile(doc: doc, typeName: label(personDocumentLabels, doc.documentType), detail: detail));
      }
      body = Column(children: rows);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DetailSectionTitle(t('documents.title')),
        WhiteBox(child: body),
      ],
    );
  }
}
