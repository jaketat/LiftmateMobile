// "Thiết bị đang đăng nhập" kiểu iOS (theo web AccountPage.tsx SessionsCard):
// nhóm "Máy này" và "Thiết bị khác", đăng xuất từng máy, hoặc đăng xuất mọi nơi khi nghi mất điện thoại / lộ mật khẩu.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/async_view.dart';
import '../../core/widgets/ios.dart';
import '../auth/session_provider.dart';
import 'account_api.dart';

final loginSessionsProvider = FutureProvider.autoDispose<List<LoginSession>>((Ref ref) => fetchLoginSessions());

String _when(DateTime d) {
  final DateTime l = d.toLocal();
  final DateTime now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  if (l.year == now.year && l.month == now.month && l.day == now.day) {
    return 'hôm nay ${two(l.hour)}:${two(l.minute)}';
  }
  return '${two(l.day)}/${two(l.month)}/${l.year}';
}

String _deviceName(LoginSession s) => (s.deviceName ?? '').isEmpty ? 'Thiết bị không rõ tên' : s.deviceName!;

class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

  Future<void> revokeAll(BuildContext context, WidgetRef ref) async {
    final bool ok = await showIosConfirm(
      context,
      title: 'Đăng xuất khỏi mọi thiết bị?',
      message: 'Tất cả thiết bị, kể cả máy này, sẽ phải đăng nhập lại. Dùng khi nghi mất điện thoại hoặc lộ mật khẩu.',
      action: 'Đăng xuất mọi nơi',
    );
    if (!ok) return;
    try {
      await revokeAllLoginSessions();
      await ref.read(sessionProvider.notifier).signOut();
    } catch (error) {
      if (context.mounted) showErrorSnackBar(context, error);
    }
  }

  Future<void> revokeOne(BuildContext context, WidgetRef ref, LoginSession s) async {
    final bool ok = await showIosConfirm(
      context,
      title: 'Đăng xuất "${_deviceName(s)}"?',
      message: 'Máy đó sẽ phải đăng nhập lại.',
      action: 'Đăng xuất',
    );
    if (!ok) return;
    try {
      await revokeLoginSession(s.publicId);
      ref.invalidate(loginSessionsProvider);
      if (context.mounted) showIosToast(context, 'Đã đăng xuất thiết bị');
    } catch (error) {
      if (context.mounted) showErrorSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<LoginSession>> value = ref.watch(loginSessionsProvider);

    final List<Widget> slivers = value.when(
      data: (List<LoginSession> list) {
        final List<LoginSession> current = list.where((LoginSession s) => s.isCurrent).toList();
        final List<LoginSession> others = list.where((LoginSession s) => !s.isCurrent).toList();
        return <Widget>[
          if (current.isNotEmpty)
            SliverToBoxAdapter(
              child: IosGroup(
                header: 'Máy này',
                dividerIndent: 62,
                children: <Widget>[for (final LoginSession s in current) _row(context, ref, s)],
              ),
            ),
          SliverToBoxAdapter(
            child: IosGroup(
              header: 'Thiết bị khác',
              dividerIndent: 62,
              footer: others.isEmpty ? null : 'Không nhận ra máy nào thì đăng xuất máy đó và đổi mật khẩu.',
              children: others.isEmpty
                  ? <Widget>[
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Không có thiết bị nào khác.',
                            style: TextStyle(fontSize: 16, color: IosColors.secondaryLabel)),
                      ),
                    ]
                  : <Widget>[for (final LoginSession s in others) _row(context, ref, s)],
            ),
          ),
          SliverToBoxAdapter(
            child: IosGroup(
              footer: 'Dùng khi nghi mất điện thoại hoặc lộ mật khẩu. Máy này cũng bị đăng xuất.',
              children: <Widget>[
                IosRow(
                  title: 'Đăng xuất khỏi mọi thiết bị',
                  destructive: true,
                  centered: true,
                  onTap: () => revokeAll(context, ref),
                ),
              ],
            ),
          ),
        ];
      },
      loading: () => const <Widget>[
        SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.only(top: 60), child: CupertinoActivityIndicator(radius: 13)),
        ),
      ],
      error: (Object error, StackTrace _) => <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 40, 32, 0),
            child: Column(
              children: <Widget>[
                Text(errorMessage(error),
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: IosColors.secondaryLabel)),
                CupertinoButton(onPressed: () => ref.invalidate(loginSessionsProvider), child: const Text('Thử lại')),
              ],
            ),
          ),
        ),
      ],
    );

    return IosPage(
      title: 'Thiết bị',
      onRefresh: () => ref.refresh(loginSessionsProvider.future),
      slivers: slivers,
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, LoginSession s) {
    return IosRow(
      icon: s.isMobile ? CupertinoIcons.device_phone_portrait : CupertinoIcons.desktopcomputer,
      iconColor: s.isCurrent ? IosColors.green : const Color(0xFF8E8E93),
      title: _deviceName(s),
      subtitle: '${s.ipAddress ?? '—'} · dùng ${_when(s.lastUsedAt ?? s.createdAt)}',
      chevron: false,
      trailing: s.isCurrent
          ? const IosPill('Đang dùng', color: IosColors.green)
          : CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: const Size(44, 44),
              onPressed: () => revokeOne(context, ref, s),
              child: const Text('Đăng xuất', style: TextStyle(fontSize: 15, color: IosColors.red)),
            ),
    );
  }
}
