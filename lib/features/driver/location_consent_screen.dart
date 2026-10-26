// T7: đồng ý chia sẻ vị trí (BR-TRK-001). Giải thích bằng lời dễ hiểu TRƯỚC khi máy hiện hộp xin quyền:
// gửi đồng ý (kèm bản điều khoản hiện hành) lên server, rồi mới xin quyền vị trí của hệ điều hành.
// Đã đồng ý thì màn này là nơi rút lại ("Tắt"). Lời theo web (ConsentScreen.tsx, LocationConsentCard.tsx).
// Luật công ty: chia sẻ vị trí là BẮT BUỘC để làm chuyến; đang làm chuyến dở thì không tắt được (location_gate.dart).
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/call.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ios.dart';
import 'driver_api.dart';
import 'driver_providers.dart';
import 'location_gate.dart';
import 'location_tracker.dart';

class LocationConsentScreen extends ConsumerStatefulWidget {
  const LocationConsentScreen({super.key});

  @override
  ConsumerState<LocationConsentScreen> createState() => _LocationConsentScreenState();
}

class _LocationConsentScreenState extends ConsumerState<LocationConsentScreen> {
  bool busy = false;
  String? warning;

  void close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/driver/trips');
    }
  }

  Future<void> restartTracking() async {
    final List<MyTrip>? trips = ref.read(driverTripsProvider).value;
    if (trips != null) {
      await ref.read(locationTrackerProvider.notifier).syncTrips(trips);
    }
    ref.invalidate(myPositionProvider);
    await ref.read(locationGateProvider.notifier).check();
  }

  Future<void> accept() async {
    setState(() {
      busy = true;
      warning = null;
    });
    try {
      await ref.read(consentProvider.notifier).accept();
      // Đồng ý xong mới xin quyền của máy
      bool granted = false;
      if (await Geolocator.isLocationServiceEnabled()) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        granted = permission == LocationPermission.whileInUse || permission == LocationPermission.always;
      }
      await restartTracking();
      if (!mounted) return;
      if (!granted) {
        setState(() {
          warning = 'Điện thoại chưa cho LiftMate lấy vị trí, nên chưa làm chuyến được. '
              'Bật GPS và cho phép "Vị trí" cho LiftMate trong Cài đặt.';
        });
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã bật chia sẻ vị trí khi chạy chuyến.')));
      close();
    } on ApiException catch (error) {
      if (error.code == 'TERMS_VERSION_OUTDATED') {
        // Điều khoản vừa đổi bản: tải lại để tài xế đọc bản mới
        await ref.read(consentProvider.notifier).reload();
      }
      if (mounted) setState(() => warning = error.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> later() async {
    await ref.read(consentProvider.notifier).decline();
    close();
  }

  Future<void> revoke() async {
    if (tripInProgress(ref.read(driverTripsProvider).value ?? const <MyTrip>[]) != null) {
      setState(() => warning = 'Đang làm chuyến: không tắt chia sẻ vị trí được cho tới khi xong chuyến.');
      return;
    }
    setState(() => busy = true);
    try {
      await ref.read(consentProvider.notifier).revoke();
      ref.read(locationTrackerProvider.notifier).stop();
      await ref.read(locationGateProvider.notifier).check();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã tắt chia sẻ vị trí. Muốn làm chuyến thì phải bật lại.')),
      );
      close();
    } on ApiException catch (error) {
      if (mounted) setState(() => warning = error.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> confirmRevoke() async {
    final bool ok = await showIosConfirm(
      context,
      title: 'Tắt chia sẻ vị trí?',
      message: 'Tắt rồi thì không bấm mốc chuyến được cho tới khi bật lại.',
      action: 'Tắt',
    );
    if (ok) await revoke();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<ConsentState> value = ref.watch(consentProvider);
    final MyTrip? running = tripInProgress(ref.watch(driverTripsProvider).value ?? const <MyTrip>[]);

    final List<Widget> slivers = value.when(
      data: (ConsentState consent) => <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            child: Column(
              children: <Widget>[
                const IosIconBadge(icon: CupertinoIcons.location_fill, color: IosColors.green, size: 72),
                const SizedBox(height: 16),
                Text(
                  consent.accepted ? 'Bạn đang chia sẻ vị trí khi chạy chuyến' : 'Chia sẻ vị trí khi chạy chuyến?',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.25, color: AppColors.text, letterSpacing: -0.4),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Để điều phối biết xe đang ở đâu và giờ dự kiến tới, khỏi phải gọi điện hỏi.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: IosColors.secondaryLabel, height: 1.4),
                ),
              ],
            ),
          ),
        ),
        if (consent.accepted)
          SliverToBoxAdapter(
            child: IosGroup(
              footerWidget: running == null
                  ? null
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(CupertinoIcons.lock_fill, size: 13, color: IosColors.secondaryLabel),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Đang làm chuyến ${running.orderCode}: không tắt được cho tới khi xong mọi điểm.',
                            style: const TextStyle(fontSize: 13, color: IosColors.secondaryLabel, height: 1.35),
                          ),
                        ),
                      ],
                    ),
              children: <Widget>[
                IosRow(
                  icon: CupertinoIcons.location_fill,
                  iconColor: IosColors.green,
                  title: 'Chia sẻ vị trí',
                  chevron: false,
                  trailing: CupertinoSwitch(
                    value: true,
                    activeTrackColor: IosColors.green,
                    onChanged: busy || running != null ? null : (bool on) {
                      if (!on) confirmRevoke();
                    },
                  ),
                ),
              ],
            ),
          ),
        SliverToBoxAdapter(
          child: IosGroup(
            header: 'Cách LiftMate dùng vị trí',
            footer: 'Bản điều khoản: ${consent.consent.currentTermsVersion}',
            dividerIndent: 62,
            children: const <Widget>[
              _Point(
                icon: CupertinoIcons.car_detailed,
                color: IosColors.blue,
                text: 'Chỉ lấy vị trí khi bạn đang chạy chuyến và app đang mở, không theo dõi ngoài giờ.',
              ),
              _Point(
                icon: CupertinoIcons.eye_fill,
                color: Color(0xFF5856D6),
                text: 'Điều phối và chủ xe xem được, để biết xe tới đâu.',
              ),
              _Point(
                icon: CupertinoIcons.clock_fill,
                color: IosColors.orange,
                text: 'Chỉ giữ vị trí mới nhất của chuyến; lưu 90 ngày rồi tự xóa.',
              ),
              _Point(
                icon: CupertinoIcons.lock_fill,
                color: Color(0xFF8E8E93),
                text: 'Bắt buộc khi làm chuyến: chưa chia sẻ thì không bấm mốc được; đang làm chuyến thì không tắt được. '
                    'Ngoài giờ chuyến, tắt lúc nào cũng được.',
              ),
            ],
          ),
        ),
        if (warning != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: IosColors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(warning!, style: const TextStyle(fontSize: 15, color: AppColors.warnText, height: 1.4)),
                    if (consent.accepted)
                      CupertinoButton(
                        padding: const EdgeInsets.only(top: 8),
                        minimumSize: const Size(44, 32),
                        onPressed: Geolocator.openAppSettings,
                        child: const Text('Mở Cài đặt của máy', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        if (!consent.accepted)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Column(
                children: <Widget>[
                  IosPillButton(
                    label: busy ? 'Đang lưu...' : 'Đồng ý và bật định vị',
                    icon: CupertinoIcons.location_fill,
                    color: AppColors.navy,
                    busy: busy,
                    onPressed: accept,
                  ),
                  CupertinoButton(
                    onPressed: busy ? null : later,
                    child: const Text('Để sau (chưa làm chuyến được)', style: TextStyle(fontSize: 16)),
                  ),
                  const Text(
                    'Bấm đồng ý xong, điện thoại sẽ hỏi quyền vị trí: chọn "Cho phép khi dùng ứng dụng".',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
      ],
      loading: () => const <Widget>[
        SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(top: 60), child: CupertinoActivityIndicator(radius: 13))),
      ],
      error: (Object error, StackTrace _) => <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 40, 32, 0),
            child: Column(
              children: <Widget>[
                Text(errorMessage(error),
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: IosColors.secondaryLabel)),
                CupertinoButton(onPressed: () => ref.invalidate(consentProvider), child: const Text('Thử lại')),
              ],
            ),
          ),
        ),
      ],
    );

    return IosPage(
      title: 'Vị trí',
      glow: IosColors.green,
      onBack: busy ? null : close,
      slivers: slivers,
    );
  }
}

/// Một dòng giải thích: ô biểu tượng màu + câu nhiều dòng
class _Point extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _Point({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          IosIconBadge(icon: icon, color: color),
          const SizedBox(width: 16),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 16, color: AppColors.text, height: 1.4))),
        ],
      ),
    );
  }
}
