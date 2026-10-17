// Màn "Thêm" (tài xế gọi là "Tài khoản"): thẻ tên, nhóm Quản lý theo quyền, đổi mật khẩu, đăng xuất.
// Theo màn N1-Them trên canvas UX/UI.
import 'package:flutter/material.dart';
// Riverpod: ConsumerWidget, WidgetRef
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push
import 'package:go_router/go_router.dart';

import '../../features/auth/session_provider.dart';
import '../session.dart';
import '../theme.dart';
import 'menu_items.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Session? session = ref.watch(sessionProvider).value;
    if (session == null) {
      return const SizedBox.shrink();
    }

    final List<AppMenuItem> items = moreItemsFor(session);

    // Nhóm "Quản lý": mỗi mục quyền cho phép là một dòng
    final List<Widget> managerRows = <Widget>[];
    for (final AppMenuItem item in items) {
      managerRows.add(
        MenuRow(
          icon: item.icon,
          label: item.label,
          onTap: () {
            // push: mở chồng lên, có nút quay lại về màn Thêm
            context.push(item.path);
          },
        ),
      );
    }

    final List<Widget> children = <Widget>[
      ProfileCard(session: session),
    ];
    // Không có mục quản lý nào (tài xế) thì bỏ cả nhóm
    if (managerRows.isNotEmpty) {
      children.add(const SectionTitle('Quản lý'));
      children.add(MenuGroup(rows: managerRows));
    }
    children.add(const SectionTitle('Tài khoản'));
    children.add(
      MenuGroup(
        rows: <Widget>[
          MenuRow(
            icon: Icons.lock_outline,
            label: 'Đổi mật khẩu',
            onTap: () {
              context.push('/change-password');
            },
          ),
          MenuRow(
            icon: Icons.logout,
            label: 'Đăng xuất',
            color: AppColors.errorText,
            showArrow: false,
            onTap: () {
              // Hộp thành null thì bảo vệ ở router đưa về /login
              ref.read(sessionProvider.notifier).signOut();
            },
          ),
        ],
      ),
    );

    // Tài xế gọi tab này là "Tài khoản"
    String title = 'Thêm';
    if (usesDriverMenu(session)) {
      title = 'Tài khoản';
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: children,
      ),
    );
  }
}

// Thẻ tên: vòng tròn chữ viết tắt, họ tên, vai trò · công ty
class ProfileCard extends StatelessWidget {
  final Session session;

  const ProfileCard({super.key, required this.session});

  // "Giám đốc Demo" thành "GD": chữ đầu của từ đầu và từ cuối
  String initials() {
    final List<String> words = session.fullName.trim().split(' ');
    String result = '';
    if (words.isNotEmpty && words.first.isNotEmpty) {
      result = words.first[0];
    }
    if (words.length > 1 && words.last.isNotEmpty) {
      result = result + words.last[0];
    }
    return result.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.navy,
            child: Text(
              initials(),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ),
          const SizedBox(width: 14),
          // Expanded: tên dài thì xuống dòng, không tràn
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.fullName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text),
                ),
                const SizedBox(height: 2),
                Text(
                  '${session.roleName} · ${session.companyName}',
                  style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Tiêu đề nhóm, vd "QUẢN LÝ"
class SectionTitle extends StatelessWidget {
  final String text;

  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

// Khung trắng bo góc chứa các dòng, giữa các dòng có vạch mảnh
class MenuGroup extends StatelessWidget {
  final List<Widget> rows;

  const MenuGroup({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[];
    for (int index = 0; index < rows.length; index++) {
      if (index > 0) {
        children.add(const Divider(height: 1, color: AppColors.border));
      }
      children.add(rows[index]);
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      // clipBehavior: cắt hiệu ứng bấm cho khỏi tràn ra góc bo
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

// Một dòng menu: ô biểu tượng, chữ, mũi tên phải
class MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool showArrow;

  const MenuRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppColors.navy,
    this.showArrow = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget? trailing;
    if (showArrow) {
      trailing = const Icon(Icons.chevron_right, color: AppColors.textMuted);
    }
    // ListTile (Flutter): dòng có biểu tượng trái, chữ giữa, phần phải; cả dòng bấm được
    return ListTile(
      minTileHeight: 56,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: color),
      ),
      title: Text(label, style: TextStyle(fontSize: 15, color: color == AppColors.navy ? AppColors.text : color)),
      trailing: trailing,
      onTap: onTap,
    );
  }
}
