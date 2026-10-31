// Màn "Thêm" (tài xế gọi là "Tài khoản"), kiểu Cài đặt của iPhone (Cupertino + Liquid Glass):
// tiêu đề lớn, thẻ kính tên người dùng, các nhóm "inset grouped" có ô biểu tượng màu,
// "Đăng xuất" là một nhóm riêng chữ đỏ ở giữa và hỏi lại trước khi thoát.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/session_provider.dart';
import '../../features/driver/driver_providers.dart';
import '../i18n.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/ios.dart';
import 'menu_items.dart';

// Màu ô biểu tượng cho nhóm Quản lý (như Cài đặt iOS: mỗi mục một màu)
const List<Color> _managerColors = <Color>[
  IosColors.blue,
  Color(0xFF5856D6),
  IosColors.orange,
  IosColors.green,
  Color(0xFFAF52DE),
  Color(0xFF32ADE6),
  IosColors.red,
  Color(0xFF8E8E93),
];

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  Future<void> signOut(BuildContext context, WidgetRef ref) async {
    final bool ok = await showIosConfirm(
      context,
      title: t('account.signOutTitle'),
      message: t('account.signOutMessage'),
      action: t('common.signOut'),
      cancel: t('common.cancel'),
    );
    if (ok) {
      // Hộp thành null thì bảo vệ ở router đưa về /login
      await ref.read(sessionProvider.notifier).signOut();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Session? session = ref.watch(sessionProvider).value;
    if (session == null) {
      return const SizedBox.shrink();
    }
    final bool isDriver = session.hasDriverProfile || usesDriverMenu(session);
    final List<AppMenuItem> items = moreItemsFor(session);

    // Trạng thái chia sẻ vị trí hiện bên phải dòng, như "Bật/Tắt" trong Cài đặt
    String? sharingValue;
    if (isDriver) {
      final bool? accepted = ref.watch(consentProvider).value?.accepted;
      sharingValue = accepted == null ? null : (accepted ? t('common.on') : t('common.off'));
    }

    // Bố cục như Cài đặt của iPhone: nhóm hồ sơ trên cùng, các nhóm không tiêu đề, Đăng xuất riêng ở cuối
    final List<Widget> slivers = <Widget>[
      SliverToBoxAdapter(
        child: IosGroup(children: <Widget>[_ProfileRow(session: session)]),
      ),
      if (items.isNotEmpty)
        SliverToBoxAdapter(
          child: IosGroup(
            dividerIndent: 62,
            children: <Widget>[
              for (int index = 0; index < items.length; index++)
                IosRow(
                  icon: items[index].icon,
                  iconColor: _managerColors[index % _managerColors.length],
                  title: items[index].label,
                  onTap: () => context.push(items[index].path),
                ),
            ],
          ),
        ),
      SliverToBoxAdapter(
        child: IosGroup(
          dividerIndent: 62,
          children: <Widget>[
            // Tài xế, phụ xe: chia sẻ vị trí khi chạy chuyến (BR-TRK-001)
            if (isDriver)
              IosRow(
                icon: CupertinoIcons.location_fill,
                iconColor: IosColors.blue,
                title: t('account.locationSharing'),
                value: sharingValue,
                onTap: () => context.push('/driver/location-consent'),
              ),
            IosRow(
              icon: CupertinoIcons.doc_text_fill,
              iconColor: IosColors.orange,
              title: t('account.documents'),
              onTap: () => context.push('/account/documents'),
            ),
          ],
        ),
      ),
      SliverToBoxAdapter(
        child: IosGroup(
          dividerIndent: 62,
          children: <Widget>[
            IosRow(
              icon: CupertinoIcons.device_phone_portrait,
              iconColor: IosColors.green,
              title: t('account.devices'),
              onTap: () => context.push('/account/devices'),
            ),
            IosRow(
              icon: CupertinoIcons.lock_fill,
              iconColor: const Color(0xFF8E8E93),
              title: t('account.changePassword'),
              onTap: () => context.push('/change-password'),
            ),
          ],
        ),
      ),
      SliverToBoxAdapter(
        child: IosGroup(
          children: <Widget>[
            IosRow(
              title: t('common.signOut'),
              destructive: true,
              centered: true,
              onTap: () => signOut(context, ref),
            ),
          ],
        ),
      ),
    ];

    return IosPage(
      title: usesDriverMenu(session) ? t('account.title') : t('account.more'),
      showBack: false,
      plain: true,
      slivers: slivers,
    );
  }
}

/// Dòng hồ sơ đầu trang (như dòng Apple Account trong Cài đặt): ảnh chữ viết tắt, họ tên, vai trò · công ty
class _ProfileRow extends StatelessWidget {
  final Session session;

  const _ProfileRow({required this.session});

  // "Giám đốc Demo" thành "GD": chữ đầu của từ đầu và từ cuối
  String initials() {
    final List<String> words = session.fullName.trim().split(RegExp(r'\s+'));
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
    final String subtitle = <String>[session.roleName, session.companyName]
        .where((String part) => part.trim().isNotEmpty)
        .join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: <Widget>[
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[Color(0xFF2B4F8E), AppColors.navy],
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              initials(),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 21),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  session.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.text, letterSpacing: -0.3),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: IosColors.secondaryLabel),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
