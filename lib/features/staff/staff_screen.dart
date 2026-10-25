// S1: danh sách nhân sự, tìm, lọc đang làm / đã khóa, bấm gọi (theo màn N4-NhanSu).
// Nhãn hạn giấy tờ lấy từ cảnh báo giấy tờ nhân sự (chỉ người có Users.ManageComplianceDocs).
import 'package:flutter/material.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push
import 'package:go_router/go_router.dart';

import '../../core/labels.dart';
import '../../core/theme.dart';
import '../fleet/shared.dart';
import 'staff_api.dart';

class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});

  @override
  ConsumerState<StaffScreen> createState() {
    return _StaffScreenState();
  }
}

class _StaffScreenState extends ConsumerState<StaffScreen> {
  String search = '';
  // 'active' hoặc 'locked'
  String? tab = 'active';

  @override
  Widget build(BuildContext context) {
    // Mỗi người lấy giấy tờ gấp nhất (ít ngày còn lại nhất)
    final Map<String, StaffAlert> alertByUser = <String, StaffAlert>{};
    if (userCan(ref, 'Users.ManageComplianceDocs')) {
      final List<StaffAlert> alerts = ref.watch(staffAlertsProvider(null)).value ?? <StaffAlert>[];
      for (final StaffAlert alert in alerts) {
        final StaffAlert? current = alertByUser[alert.userPublicId];
        if (current == null || alert.daysRemaining < current.daysRemaining) {
          alertByUser[alert.userPublicId] = alert;
        }
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Nhân sự')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchField(
              hint: 'Tìm tên, SĐT, email…',
              onChanged: (String text) {
                setState(() {
                  search = text;
                });
              },
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChips(
              options: const <String?, String>{'active': 'Đang làm', 'locked': 'Đã khóa'},
              selected: tab,
              onSelected: (String? value) {
                setState(() {
                  tab = value;
                });
              },
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: PagedList<StaffUser>(
              key: ValueKey<String>('$search|$tab'),
              fetchPage: (int pageNumber) {
                return fetchStaff(pageNumber, search, tab == 'active');
              },
              emptyText: 'Không có nhân sự nào.',
              itemBuilder: (StaffUser user) {
                return StaffCard(user: user, alert: alertByUser[user.publicId]);
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Mời nhân viên mới, phân quyền chi tiết làm trên web.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class StaffCard extends StatelessWidget {
  final StaffUser user;
  final StaffAlert? alert;

  const StaffCard({super.key, required this.user, this.alert});

  @override
  Widget build(BuildContext context) {
    String subtitle = user.roleDisplay;
    if (user.licenseClass != null) {
      subtitle = '$subtitle · bằng ${user.licenseClass}';
    }
    Color alertColor = AppColors.warnText;
    if (alert != null && alert!.daysRemaining <= 3) {
      alertColor = AppColors.errorText;
    }
    String alertText = '';
    if (alert != null) {
      final String docName = label(personDocumentLabels, alert!.documentType);
      alertText = alert!.daysRemaining < 0 ? '$docName đã hết hạn' : '$docName còn ${alert!.daysRemaining} ngày';
    }

    return TapCard(
      onTap: () {
        context.push('/staff/${user.publicId}');
      },
      child: Row(
        children: [
          InitialsAvatar(user.fullName, isMuted: !user.isActive),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.fullName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                if (alert != null)
                  Text(alertText, style: TextStyle(fontSize: 13, color: alertColor, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          if (user.phone.isNotEmpty)
            IconButton(
              tooltip: 'Gọi ${user.phone}',
              icon: const Icon(Icons.call_outlined, color: AppColors.navy),
              onPressed: () {
                callPhone(context, user.phone);
              },
            ),
        ],
      ),
    );
  }
}
