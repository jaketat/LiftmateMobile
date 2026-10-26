// Màn "Thêm" (tài xế gọi là "Tài khoản"), kiểu Cài đặt của iPhone (Cupertino + Liquid Glass):
// tiêu đề lớn, thẻ kính tên người dùng, các nhóm "inset grouped" có ô biểu tượng màu,
// "Đăng xuất" là một nhóm riêng chữ đỏ ở giữa và hỏi lại trước khi thoát.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/session_provider.dart';
import '../../features/driver/driver_providers.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/glass.dart';
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
      title: 'Đăng xuất?',
      message: 'Bạn sẽ cần đăng nhập lại để xem chuyến và báo hỏng.',
      action: 'Đăng xuất',
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
      sharingValue = accepted == null ? null : (accepted ? 'Bật' : 'Tắt');
    }

    final List<Widget> slivers = <Widget>[
      SliverToBoxAdapter(child: _ProfileCard(session: session)),
      if (items.isNotEmpty)
        SliverToBoxAdapter(
          child: IosGroup(
            header: 'Quản lý',
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
          header: 'Tài khoản',
          dividerIndent: 62,
          children: <Widget>[
            IosRow(
              icon: CupertinoIcons.doc_text_fill,
              iconColor: IosColors.blue,
              title: 'Giấy tờ của tôi',
              onTap: () => context.push('/account/documents'),
            ),
            // Tài xế, phụ xe: chia sẻ vị trí khi chạy chuyến (BR-TRK-001)
            if (isDriver)
              IosRow(
                icon: CupertinoIcons.location_fill,
                iconColor: IosColors.green,
                title: 'Chia sẻ vị trí',
                value: sharingValue,
                onTap: () => context.push('/driver/location-consent'),
              ),
          ],
        ),
      ),
      SliverToBoxAdapter(
        child: IosGroup(
          header: 'Bảo mật',
          dividerIndent: 62,
          children: <Widget>[
            IosRow(
              icon: CupertinoIcons.device_phone_portrait,
              iconColor: const Color(0xFF5856D6),
              title: 'Thiết bị đang đăng nhập',
              onTap: () => context.push('/account/devices'),
            ),
            IosRow(
              icon: CupertinoIcons.lock_fill,
              iconColor: const Color(0xFF8E8E93),
              title: 'Đổi mật khẩu',
              onTap: () => context.push('/change-password'),
            ),
          ],
        ),
      ),
      SliverToBoxAdapter(
        child: IosGroup(
          children: <Widget>[
            IosRow(
              title: 'Đăng xuất',
              destructive: true,
              centered: true,
              onTap: () => signOut(context, ref),
            ),
          ],
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'LiftMate · ${session.companyName}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: IosColors.secondaryLabel),
          ),
        ),
      ),
    ];

    return IosPage(
      title: usesDriverMenu(session) ? 'Tài khoản' : 'Thêm',
      showBack: false,
      slivers: slivers,
    );
  }
}

/// Thẻ kính tên người dùng: ảnh chữ viết tắt lớn, họ tên, vai trò · công ty
class _ProfileCard extends StatelessWidget {
  final Session session;

  const _ProfileCard({required this.session});

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      child: Glass(
        opacity: 0.6,
        borderRadius: BorderRadius.circular(26),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Container(
              width: 62,
              height: 62,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[Color(0xFF2B4F8E), AppColors.navy],
                ),
                boxShadow: <BoxShadow>[BoxShadow(color: Color(0x330C2858), blurRadius: 12, offset: Offset(0, 4))],
              ),
              alignment: Alignment.center,
              child: Text(
                initials(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 22),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    session.fullName,
                    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600, color: AppColors.text, letterSpacing: -0.3),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    session.roleName,
                    style: const TextStyle(fontSize: 15, color: IosColors.secondaryLabel),
                  ),
                  Text(
                    session.companyName,
                    style: const TextStyle(fontSize: 15, color: IosColors.secondaryLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
