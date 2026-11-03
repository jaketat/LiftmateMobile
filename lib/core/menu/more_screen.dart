// Màn "Thêm" (tài xế gọi là "Tài khoản"), kiểu Cài đặt của iPhone (Cupertino + Liquid Glass):
// tiêu đề lớn, thẻ kính tên người dùng, các nhóm "inset grouped" có ô biểu tượng màu,
// "Đăng xuất" là một nhóm riêng chữ đỏ ở giữa và hỏi lại trước khi thoát.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/app_lock.dart';
import '../../features/auth/session_provider.dart';
import '../../features/driver/driver_providers.dart';
import '../i18n.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/ios.dart';
import 'menu_items.dart';
import '../widgets/user_avatar.dart';

// Màu ô biểu tượng cho nhóm Quản lý (như Cài đặt iOS: mỗi mục một màu)
List<Color> get _managerColors => <Color>[
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
    final BiometricKind? biometricKind = ref.watch(biometricKindProvider).value;

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
            // Máy không hỗ trợ thì ẩn, trừ khi đang bật: gỡ mật mã máy sau khi bật thì vẫn phải tắt được
            if (canUseAppLock(session) && biometricKind != null && (biometricKind != BiometricKind.none || (ref.watch(appLockProvider).value?.isEnabledFor(session.userId) ?? false)))
              _AppLockRow(session: session, kind: biometricKind),
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

/// Dòng hồ sơ đầu trang (như dòng Apple Account trong Cài đặt), bấm vào xem thông tin cá nhân: ảnh đại diện, họ tên, vai trò · công ty
class _ProfileRow extends StatelessWidget {
  final Session session;

  const _ProfileRow({required this.session});

  @override
  Widget build(BuildContext context) {
    final String subtitle = <String>[session.roleName, session.companyName]
        .where((String part) => part.trim().isNotEmpty)
        .join(' · ');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/account/profile'),
      child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: <Widget>[
          UserAvatar(name: session.fullName, url: session.avatarUrl, size: 58),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  session.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.text, letterSpacing: -0.3),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel),
                  ),
              ],
            ),
          ),
          Icon(CupertinoIcons.chevron_forward, size: 18, color: IosColors.tertiaryLabel),
        ],
      ),
      ),
    );
  }
}

/// Công tắc khóa app. Bật hay tắt đều phải xác thực trước, để người cầm máy đang mở sẵn không tự tắt được.
class _AppLockRow extends ConsumerStatefulWidget {
  final Session session;
  final BiometricKind kind;

  const _AppLockRow({required this.session, required this.kind});

  @override
  ConsumerState<_AppLockRow> createState() => _AppLockRowState();
}

class _AppLockRowState extends ConsumerState<_AppLockRow> {
  bool busy = false;

  Future<void> toggle(bool next) async {
    if (busy) return;
    setState(() => busy = true);
    final BiometricResult result = await ref.read(biometricAuthProvider).authenticate();
    if (!mounted) return;
    setState(() => busy = false);
    if (result == BiometricResult.failed) {
      showIosToast(context, t('appLock.failed'), isError: true);
    }
    if (result != BiometricResult.success) return;
    final AppLockNotifier lock = ref.read(appLockProvider.notifier);
    try {
      await (next ? lock.enable(widget.session.userId) : lock.disable());
    } catch (error) {
      debugPrint('Không lưu được cài đặt khóa app: $error');
      if (mounted) showIosToast(context, t('appLock.saveFailed'), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool enrolled = widget.kind.isUsable;
    final bool enabled = ref.watch(appLockProvider).value?.isEnabledFor(widget.session.userId) ?? false;
    return IosRow(
      leading: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: IosColors.blue),
        child: BiometricIcon(kind: widget.kind, size: 19, color: Colors.white),
      ),
      title: enrolled ? t('appLock.toggle', <String, Object?>{'name': widget.kind.displayName}) : t('appLock.toggleGeneric'),
      // Chỉ nhắc khi máy chưa cài sinh trắc, lúc đó công tắc không bật được
      subtitle: enrolled ? null : t('appLock.notEnrolled'),
      chevron: false,
      // Máy chưa cài sinh trắc mà khóa đang bật thì vẫn cho tắt, nhưng phải đăng nhập lại bằng mật khẩu mới tới được đây
      trailing: AdaptiveSwitch(
        value: enabled,
        activeColor: IosColors.green,
        onChanged: enrolled && !busy ? toggle : (enabled && !enrolled ? (bool _) => ref.read(appLockProvider.notifier).disable() : null),
      ),
    );
  }
}
