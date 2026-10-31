// "Thiết bị đang đăng nhập" kiểu iOS (theo web AccountPage.tsx SessionsCard):
// nhóm "Máy này" và "Thiết bị khác", đăng xuất từng máy, hoặc đăng xuất mọi nơi khi nghi mất điện thoại / lộ mật khẩu.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
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
    return t('devices.todayAt', {'time': '${two(l.hour)}:${two(l.minute)}'});
  }
  return '${two(l.day)}/${two(l.month)}/${l.year}';
}

String _deviceName(LoginSession s) => (s.deviceName ?? '').isEmpty ? t('devices.unknown') : s.deviceName!;

class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

  Future<void> revokeAll(BuildContext context, WidgetRef ref) async {
    final bool ok = await showIosConfirm(
      context,
      title: t('devices.signOutAllTitle'),
      message: t('devices.signOutAllMessage'),
      action: t('devices.signOutAllAction'),
      cancel: t('common.cancel'),
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
      title: t('devices.signOutOneTitle', {'name': _deviceName(s)}),
      message: t('devices.signOutOneMessage'),
      action: t('common.signOut'),
      cancel: t('common.cancel'),
    );
    if (!ok) return;
    try {
      await revokeLoginSession(s.publicId);
      ref.invalidate(loginSessionsProvider);
      if (context.mounted) showIosToast(context, t('devices.signedOut'));
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
                header: t('devices.thisDevice'),
                dividerIndent: 62,
                children: <Widget>[for (final LoginSession s in current) _row(context, ref, s)],
              ),
            ),
          SliverToBoxAdapter(
            child: IosGroup(
              header: t('devices.otherDevices'),
              dividerIndent: 62,
              children: others.isEmpty
                  ? <Widget>[
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(t('devices.noOthers'),
                            style: const TextStyle(fontSize: 16, color: IosColors.secondaryLabel)),
                      ),
                    ]
                  : <Widget>[for (final LoginSession s in others) _row(context, ref, s)],
            ),
          ),
          SliverToBoxAdapter(
            child: IosGroup(
              children: <Widget>[
                IosRow(
                  title: t('devices.signOutAll'),
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
                CupertinoButton(onPressed: () => ref.invalidate(loginSessionsProvider), child: Text(t('common.retry'))),
              ],
            ),
          ),
        ),
      ],
    );

    return IosPage(
      title: t('devices.title'),
      onRefresh: () => ref.refresh(loginSessionsProvider.future),
      slivers: slivers,
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, LoginSession s) {
    return IosRow(
      icon: s.isMobile ? CupertinoIcons.device_phone_portrait : CupertinoIcons.desktopcomputer,
      iconColor: s.isCurrent ? IosColors.green : const Color(0xFF8E8E93),
      title: _deviceName(s),
      subtitle: t('devices.lastUsed', {'ip': s.ipAddress ?? '—', 'when': _when(s.lastUsedAt ?? s.createdAt)}),
      chevron: false,
      trailing: s.isCurrent
          ? IosPill(t('devices.current'), color: IosColors.green)
          : CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: const Size(44, 44),
              onPressed: () => revokeOne(context, ref, s),
              child: Text(t('common.signOut'), style: const TextStyle(fontSize: 15, color: IosColors.red)),
            ),
    );
  }
}
