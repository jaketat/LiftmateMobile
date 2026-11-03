// Màn xem thông tin cá nhân, mở từ dòng hồ sơ ở Tài khoản. Dữ liệu là của GET /auth/me (sessionProvider).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/ios.dart';
import '../../core/widgets/user_avatar.dart';
import 'session_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    // Lấy lại thông tin mới nhất (vd vừa đổi ảnh trên web). Lỗi mạng thì vẫn hiện dữ liệu đang có
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) refresh().ignore();
    });
  }

  Future<void> refresh() => ref.read(sessionProvider.notifier).reload();

  @override
  Widget build(BuildContext context) {
    final Session? session = ref.watch(sessionProvider).value;
    if (session == null) {
      return const SizedBox.shrink();
    }
    final String subtitle = <String>[session.roleName, session.companyName]
        .where((String part) => part.trim().isNotEmpty)
        .join(' · ');
    final DateTime? joinedAt = session.joinedAt;
    final String? email = session.email;

    return IosPage(
      title: t('profile.title'),
      onRefresh: refresh,
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: Column(
              children: <Widget>[
                UserAvatar(name: session.fullName, url: session.avatarUrl, size: 104),
                const SizedBox(height: 12),
                Text(
                  session.fullName,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text, letterSpacing: -0.3),
                ),
                if (subtitle.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: IosColors.secondaryLabel),
                  ),
                ],
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: IosGroup(
            children: <Widget>[
              IosRow(title: t('profile.username'), value: session.username, chevron: false),
              IosRow(title: t('profile.phone'), value: session.phone, chevron: false),
              IosRow(title: t('profile.email'), value: email ?? t('profile.noEmail'), chevron: false),
              if (joinedAt != null)
                IosRow(title: t('profile.joined'), value: dateFormat.format(joinedAt.toLocal()), chevron: false),
            ],
          ),
        ),
      ],
    );
  }
}
