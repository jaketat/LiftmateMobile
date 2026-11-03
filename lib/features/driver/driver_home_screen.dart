// T1: trang chủ tài xế, bố cục kiểu Grab Driver, phong cách Liquid Glass.
// Canvas trang "Tài xế · Bản đồ, Liquid Glass": TX-TrangChu (chưa chia sẻ), TX-TrangChuDangChay
// (đang chia sẻ, có chuyến), TX-DanhSachChuyen (kéo sheet lên).
// - Trên: viên "Hôm nay · N chuyến" (trái), vai trò + ảnh đại diện (phải).
// - Giữa bản đồ: nút lớn. Chưa chia sẻ → "Bật chia sẻ vị trí". Đang chia sẻ, có chuyến → "Tiếp theo: ...".
// - Sheet kính: dòng trạng thái chia sẻ, 5 ô việc nhanh, thẻ chuyến tiếp theo; kéo lên xem mọi chuyến.
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:vietmap_flutter_gl/vietmap_flutter_gl.dart' show LatLng, VietmapController;

import '../../core/api/call.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/ios.dart';
import '../../core/widgets/page_transition.dart';
import '../../core/widgets/user_avatar.dart';
import '../auth/ripple_transition.dart';
import '../auth/session_provider.dart';
import 'driver_api.dart';
import 'driver_providers.dart';
import 'driver_widgets.dart';
import 'location_gate.dart';
import 'location_tracker.dart';
import 'trip_logic.dart';
import 'trip_map.dart';
import '../../core/i18n.dart';

const double sheetCollapsed = 0.46;
const double sheetMin = 0.24;
const double sheetExpanded = 0.92;
// Thanh trên và các nút nổi: sheet cao tới mức này thì ẩn hẳn, mờ dần trong đoạn ngay trước đó
const double floatingHiddenAt = 0.6;
const double floatingFadeRange = 0.1;

class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen> {
  final DraggableScrollableController sheet = DraggableScrollableController();
  // Có khi bản đồ Vietmap tạo xong (nút "Về vị trí của tôi" dùng)
  VietmapController? map;
  // Không setState theo sheet: kéo sheet chỉ dịch các nút nổi, không dựng lại bản đồ và danh sách chuyến
  final ValueNotifier<double> sheetSize = ValueNotifier<double>(sheetCollapsed);
  // true trong lúc sheet đang di chuyển và một nhịp ngắn sau đó
  final ValueNotifier<bool> sheetMoving = ValueNotifier<bool>(false);
  Timer? sheetIdle;
  // 0 Hôm nay, 1 Sắp tới, 2 Đã qua
  int filter = 0;

  @override
  void initState() {
    super.initState();
    sheet.addListener(() {
      if (!mounted || !sheet.isAttached) return;
      sheetSize.value = sheet.size;
      sheetMoving.value = true;
      sheetIdle?.cancel();
      sheetIdle = Timer(const Duration(milliseconds: 180), () => sheetMoving.value = false);
    });
    // Danh sách chuyến tải xong thì chọn chuyến đang chạy để gửi vị trí (T8)
    ref.listenManual<AsyncValue<List<MyTrip>>>(driverTripsProvider,
        (AsyncValue<List<MyTrip>>? previous, AsyncValue<List<MyTrip>> next) {
      final List<MyTrip>? trips = next.value;
      if (next is AsyncData<List<MyTrip>> && trips != null) {
        ref.read(locationTrackerProvider.notifier).syncTrips(trips);
      }
    }, fireImmediately: true);
    // Không tự mở màn hỏi đồng ý: tài xế bật thẳng bằng công tắc trên bản đồ (điều khoản đầy đủ ở Tài khoản › Chia sẻ vị trí)
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!gateListening) {
      gateListening = true;
      // Định vị vừa sẵn sàng lại (bật GPS, cấp quyền, đồng ý) thì bật lại vòng gửi vị trí
      ref.listenManual<LocationGate>(locationGateProvider, (LocationGate? previous, LocationGate next) {
        final List<MyTrip>? trips = ref.read(driverTripsProvider).value;
        if (trips == null) return;
        if (next == LocationGate.ready) {
          ref.read(locationTrackerProvider.notifier).syncTrips(trips);
          ref.invalidate(myPositionProvider);
        }
      });
    }
  }

  bool gateListening = false;

  @override
  void dispose() {
    sheetIdle?.cancel();
    sheet.dispose();
    sheetSize.dispose();
    sheetMoving.dispose();
    super.dispose();
  }

  // Mờ dần theo chiều cao sheet. Mờ hết thì chỉ ẩn, giữ nguyên view native để kéo xuống lại không phải tạo lại
  Widget _fadeWithSheet(double size, Widget child) {
    final double opacity = ((floatingHiddenAt - size) / floatingFadeRange).clamp(0.0, 1.0);
    return Visibility(
      visible: opacity > 0,
      maintainState: true,
      maintainAnimation: true,
      child: IgnorePointer(
        ignoring: opacity < 1,
        child: Opacity(opacity: opacity, child: child),
      ),
    );
  }

  void openTrip(MyTrip trip) {
    context.push('/driver/trips/${trip.publicId}');
  }

  void expandSheet() {
    if (sheet.isAttached) {
      sheet.animateTo(sheetExpanded, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    }
  }

  void snack(String text, {bool isError = true}) {
    showIosToast(context, text, isError: isError);
  }

  /// Nút tải lại: lấy lại danh sách chuyến và trạng thái đồng ý vị trí
  Future<void> reloadTrips() async {
    HapticFeedback.lightImpact();
    ref.invalidate(consentProvider);
    try {
      await ref.refresh(driverTripsProvider.future);
    } catch (error) {
      if (mounted) snack(errorMessage(error));
    }
  }

  // Đang bật / tắt chia sẻ vị trí (khóa công tắc cho tới khi xong)
  bool switching = false;

  /// Công tắc chia sẻ vị trí ngay trên bản đồ, không mở màn hỏi:
  /// - Bật: chưa đồng ý thì gửi đồng ý luôn (bản điều khoản hiện hành), rồi xin quyền vị trí của máy;
  ///   GPS tắt / bị chặn quyền thì mở đúng chỗ Cài đặt.
  /// - Tắt: rút đồng ý, dừng gửi vị trí. Đang làm chuyến dở thì không cho tắt (luật công ty).
  Future<void> setSharing(bool on) async {
    if (switching) return;
    final List<MyTrip> trips = ref.read(driverTripsProvider).value ?? const <MyTrip>[];
    if (!on && tripInProgress(trips) != null) {
      snack(t('location.lockedDuringTrip'));
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => switching = true);
    try {
      final LocationGateNotifier gate = ref.read(locationGateProvider.notifier);
      if (on) {
        if (!(ref.read(consentProvider).value?.accepted ?? false)) {
          await ref.read(consentProvider.notifier).accept();
          // Đồng ý xong mới xin quyền của máy
          if (await Geolocator.isLocationServiceEnabled()) {
            final LocationPermission permission = await Geolocator.checkPermission();
            if (permission == LocationPermission.denied) {
              await Geolocator.requestPermission();
            }
          }
          await gate.check();
        }
        if (ref.read(locationGateProvider) != LocationGate.ready) {
          await gate.fix();
        }
        await ref.read(locationTrackerProvider.notifier).syncTrips(trips);
        ref.invalidate(myPositionProvider);
      } else {
        await ref.read(consentProvider.notifier).revoke();
        await gate.check();
        if (ref.read(consentProvider).value?.accepted ?? false) {
          // Máy chủ vẫn ghi là đang bật: báo thật, không giả vờ đã tắt
          if (mounted) snack(t('location.turnOffFailed'));
        } else {
          ref.read(locationTrackerProvider.notifier).stop();
          if (mounted) snack(t('location.turnedOff'), isError: false);
        }
      }
    } on ApiException catch (error) {
      if (error.code == 'TERMS_VERSION_OUTDATED') {
        await ref.read(consentProvider.notifier).reload();
      }
      if (mounted) snack(error.message);
    } catch (error) {
      if (mounted) snack(errorMessage(error));
    } finally {
      if (mounted) setState(() => switching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Session? session = ref.watch(sessionProvider).value;
    final AsyncValue<List<MyTrip>> tripsValue = ref.watch(driverTripsProvider);
    final ConsentState? consent = ref.watch(consentProvider).value;
    final TrackerState tracker = ref.watch(locationTrackerProvider);
    final Position? position = tracker.lastPosition ?? ref.watch(myPositionProvider).value;
    final LatLng? me = position == null ? null : LatLng(position.latitude, position.longitude);

    final List<MyTrip> trips = tripsValue.value ?? const <MyTrip>[];
    final TripGroups groups = groupTrips(trips, DateTime.now());
    final MyTrip? featured = featuredTrip(groups);
    final LocationGate gate = ref.watch(locationGateProvider);
    final bool sharing = gate == LocationGate.ready || (gate == LocationGate.checking && (consent?.accepted ?? false));
    final bool tripRunning = featured != null && featured.trackingActive && featured.nextAction != null;

    final MediaQueryData media = MediaQuery.of(context);
    final double screenHeight = media.size.height;
    // Khoảng cách từ mép sheet tới các nút nổi; lớp nút được dịch theo mép sheet ở dưới
    const double aboveSheet = 16;
    final EdgeInsets mapPadding = EdgeInsets.fromLTRB(48, media.padding.top + 100, 48, screenHeight * sheetCollapsed + 90);

    return Scaffold(
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            // Bản đồ tạo sau khi hiệu ứng vào màn chính chạy xong, không làm giật hiệu ứng
            child: AfterEntrance(
              child: TripMap(
                onMapCreated: (VietmapController created) => map = created,
                // Trang chủ chỉ có vị trí của tôi; điểm đi, điểm đến chỉ hiện khi mở một chuyến
                stops: const <TripStop>[],
                me: me,
                fitPadding: mapPadding,
              ),
            ),
          ),
          // Mép trên bản đồ mờ dần sau các viên kính (progressive blur), như Apple Maps
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: ProgressiveBlur(height: media.padding.top + 76, maxSigma: 8, tintOpacity: 0.25),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: media.padding.top + 12,
            // Sheet kéo lên cao thì mờ dần rồi ẩn: kính của sheet không làm mờ được phần Flutter vẽ, thanh này sẽ lộ qua sheet
            child: ValueListenableBuilder<double>(
              valueListenable: sheetSize,
              builder: (BuildContext context, double size, Widget? bar) => _fadeWithSheet(size, bar!),
              child: _TopBar(
                session: session,
                todayCount: groups.today.length,
                role: featured?.myRole,
                onTrips: expandSheet,
                onAccount: () => pushTabRoot(context, '/more'),
              ),
            ),
          ),
          // Các nút nổi bám mép sheet: chỉ dịch hình theo sheet, không dựng lại. Sheet kéo lên cao thì mờ dần rồi ẩn.
          Positioned.fill(
            child: ValueListenableBuilder<double>(
              valueListenable: sheetSize,
              builder: (BuildContext context, double size, Widget? controls) {
                return _fadeWithSheet(size, Transform.translate(offset: Offset(0, -screenHeight * size), child: controls));
              },
              child: NativeViewsPause(paused: sheetMoving, child: Stack(
                children: <Widget>[
                  // Đang chạy chuyến: nút lớn "Tiếp theo: ..." nằm trên thanh chia sẻ vị trí
                  if (sharing && tripRunning)
                    Positioned(
                      // Chừa cột nút tròn bên phải để không đè lên nút đổi bản đồ
                      left: 16,
                      right: 74,
                      bottom: aboveSheet + 66,
                      child: Center(
                        child: _MainButton(
                          sharing: sharing,
                          consent: consent,
                          featured: featured,
                          gate: gate,
                          onTurnOn: () => setSharing(true),
                          onOpenTrip: openTrip,
                        ),
                      ),
                    ),
                  // Thanh kính nổi riêng trên sheet: trạng thái + công tắc bật / tắt chia sẻ vị trí
                  Positioned(
                    left: 16,
                    right: 74,
                    bottom: aboveSheet,
                    child: _StatusLine(
                      gate: gate,
                      tracker: tracker,
                      locked: tripInProgress(trips) != null,
                      busy: switching,
                      onChanged: setSharing,
                    ),
                  ),
                  // Đổi bản đồ thường / vệ tinh, ngay trên nút định vị
                  const Positioned(
                    right: 16,
                    bottom: aboveSheet + 58,
                    child: MapStyleButton(),
                  ),
                  Positioned(
                    right: 16,
                    bottom: aboveSheet,
                    child: GlassCircleButton(
                      nativeSymbol: 'location',
                      icon: CupertinoIcons.location,
                      tooltip: t('map.myLocation'),
                      size: 48,
                      onPressed: me == null ? null : () => map?.animateCamera(focusCamera(me, mapPadding)),
                    ),
                  ),
                ],
              )),
            ),
          ),
          DraggableScrollableSheet(
            controller: sheet,
            initialChildSize: sheetCollapsed,
            minChildSize: sheetMin,
            maxChildSize: sheetExpanded,
            snap: true,
            snapSizes: const <double>[sheetCollapsed],
            builder: (BuildContext context, ScrollController scroll) {
              return GlassTouchFeedback(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(GlassSheetSurface.radius)),
                child: GlassSheetSurface(
                  raised: sheetSize,
                  // Nền kính hơi xám như bảng của iOS để các thẻ trắng nổi lên
                  fill: IosColors.groupedBackground,
                  child: NativeViewsPause(
                    paused: sheetMoving,
                    child: AsyncView<List<MyTrip>>(
                    value: tripsValue,
                    onRetry: () => ref.invalidate(driverTripsProvider),
                    builder: (List<MyTrip> _) {
                      return _sheetList(scroll, groups, featured, consent, tracker, media.padding.bottom);
                    },
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _sheetList(
    ScrollController scroll,
    TripGroups groups,
    MyTrip? featured,
    ConsentState? consent,
    TrackerState tracker,
    double bottomInset,
  ) {
    final List<Widget> children = <Widget>[const SheetGrabber()];
    final bool reloading = ref.watch(driverTripsProvider).isLoading;

    // Đầu sheet: tiêu đề lớn + nút tải lại tròn kính
    children.add(Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 0, 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              t('home.title'),
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text, letterSpacing: -0.4),
            ),
          ),
          Semantics(
            button: true,
            label: t('common.reload'),
            excludeSemantics: true,
            child: Builder(builder: (BuildContext context) {
              final Widget flutterButton = GestureDetector(
              onTap: reloading ? null : reloadTrips,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.raised.withValues(alpha: 0.9),
                  border: Border.all(color: AppColors.raised),
                  boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x140C2858), blurRadius: 10, offset: Offset(0, 3))],
                ),
                alignment: Alignment.center,
                child: reloading
                    ? const CupertinoActivityIndicator(radius: 9)
                    : Icon(CupertinoIcons.arrow_clockwise, size: 19, color: AppColors.navy),
              ),
            );
              // Đang tải vẫn dùng vòng xoay Flutter; nút native không có trạng thái này
              if (reloading) return flutterButton;
              return NativeSwap(
                native: () => NativeGlassButton(
                    symbol: 'arrow.clockwise',
                    label: t('common.reload'),
                    size: 40,
                    iconSize: 15,
                    foreground: AppColors.navy,
                    onPressed: reloadTrips,
                ),
                fallback: flutterButton,
              );
            }),
          ),
        ],
      ),
    ));

    // Nhắc nộp ảnh / biên bản cho chuyến gần nhất đã dỡ hàng hoặc đã xong
    MyTrip? dueTrip;
    for (final MyTrip trip in <MyTrip>[...groups.today, ...groups.past]) {
      if (docsDue(trip)) {
        dueTrip = trip;
        break;
      }
    }
    if (dueTrip != null) {
      children.add(DocsReminderCard(trip: dueTrip, showTrip: true));
    }

    // Bộ lọc kiểu iOS
    children.add(GlassSegmented(
      labels: <String>[
        t('home.filter.todayCount', <String, Object?>{'count': groups.today.length}),
        t('home.filter.upcomingCount', <String, Object?>{'count': groups.upcoming.length}),
        t('home.filter.past'),
      ],
      selected: filter,
      onChanged: (int value) => setState(() => filter = value),
    ));

    final List<MyTrip> shown = filter == 0 ? groups.today : (filter == 1 ? groups.upcoming : groups.past);
    children.add(SheetSectionTitle(filter == 0 ? t('home.filter.today') : (filter == 1 ? t('home.filter.upcoming') : t('home.filter.past'))));
    if (groups.total == 0) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          t('home.empty.all'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: IosColors.secondaryLabel, height: 1.4),
        ),
      ));
    } else if (shown.isEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          filter == 0
              ? t('home.empty.today')
              : (filter == 1 ? t('home.empty.upcoming') : t('home.empty.past')),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: IosColors.secondaryLabel),
        ),
      ));
    }
    for (int index = 0; index < shown.length; index++) {
      if (index > 0) children.add(const SizedBox(height: 10));
      final MyTrip trip = shown[index];
      children.add(TripCard(
        trip: trip,
        withDay: filter != 0,
        // Chuyến đang chạy / tiếp theo được viền nổi bật
        featured: filter == 0 && trip.publicId == featured?.publicId,
        onTap: () => openTrip(trip),
      ));
    }

    // Việc nhanh
    children.add(SheetSectionTitle(t('home.quickActions')));
    children.add(_QuickTiles(
      onTrips: () {
        setState(() => filter = 0);
        expandSheet();
      },
      onPhotos: () {
        if (featured == null) {
          snack(t('home.noTripForPhotos'));
        } else {
          context.push('/driver/trips/${featured.publicId}/documents');
        }
      },
      onBreakdown: () {
        if (featured == null) {
          context.push('/driver/breakdowns/new');
        } else {
          context.push('/driver/trips/${featured.publicId}/breakdown');
        }
      },
      onNavigate: () {
        final TripStop? stop = _nextStop(featured);
        if (stop == null) {
          snack(t('home.noStopToNavigate'));
        } else {
          navigateTo(context, stop);
        }
      },
      onMore: () => pushTabRoot(context, '/more'),
    ));
    children.add(const MapAttribution());

    return ListView(
      controller: scroll,
      // Chừa chỗ cho thanh tab nổi (extendBody đưa chiều cao thanh vào padding đáy)
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset + 24),
      children: children,
    );
  }

  TripStop? _nextStop(MyTrip? trip) {
    if (trip == null || trip.stops.isEmpty) {
      return null;
    }
    final NextAction? next = trip.nextAction;
    if (next != null) {
      // Đang ở điểm (đã tới, chưa rời) thì dẫn tới điểm sau đó
      final TripStop? current = trip.stopAt(next.stopSequence);
      if (current != null && next.kind != 'Arrived') {
        for (final TripStop stop in trip.stops) {
          if (stop.sequence > current.sequence) return stop;
        }
      }
      return current;
    }
    return trip.stops.first;
  }
}

class _TopBar extends StatelessWidget {
  final Session? session;
  final int todayCount;
  final String? role;
  final VoidCallback onTrips;
  final VoidCallback onAccount;

  const _TopBar({
    required this.session,
    required this.todayCount,
    required this.role,
    required this.onTrips,
    required this.onAccount,
  });

  Widget _pill({required Widget child, required VoidCallback onTap, required EdgeInsets padding, String? semantics}) {
    return Semantics(
      button: true,
      label: semantics,
      child: Glass(
        nativeSurface: true,
        borderRadius: BorderRadius.circular(24),
        opacity: 0.66,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(height: 48, child: Padding(padding: padding, child: child)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String name = session?.fullName ?? '';
    final String roleText = role == null ? (session?.roleName ?? '') : tEnum('crewRole', role);
    // Tên gọi (chữ cuối của họ tên), như iPhone hiện tên: "Trần Hữu Hùng" → "Hùng"
    final List<String> words = name.trim().split(RegExp(r'\s+'));
    final String shortName = words.isEmpty || words.last.isEmpty ? name : words.last;
    return Row(
      children: <Widget>[
        Flexible(
          child: _pill(
            onTap: onTrips,
            padding: const EdgeInsets.fromLTRB(12, 0, 16, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.local_shipping_outlined, size: 20, color: AppColors.navy),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    t('home.todayTrips', <String, Object?>{'count': todayCount}),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        _pill(
          onTap: onAccount,
          semantics: t('home.account', <String, Object?>{'name': name}),
          padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Tên tài xế ở trên, vai trò trong chuyến nhỏ ở dưới
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      shortName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.15),
                    ),
                    if (roleText.isNotEmpty)
                      Text(
                        roleText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.15),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              UserAvatar(name: name, url: session?.avatarUrl, size: 40),
            ],
          ),
        ),
      ],
    );
  }
}

/// Nút lớn giữa bản đồ (vai trò như "Go Online" của Grab)
class _MainButton extends StatelessWidget {
  final bool sharing;
  final LocationGate gate;
  final ConsentState? consent;
  final MyTrip? featured;
  final VoidCallback onTurnOn;
  final void Function(MyTrip trip) onOpenTrip;

  const _MainButton({
    required this.sharing,
    required this.gate,
    required this.consent,
    required this.featured,
    required this.onTurnOn,
    required this.onOpenTrip,
  });

  @override
  Widget build(BuildContext context) {
    String text;
    IconData icon;
    Color iconBackground;
    VoidCallback? onTap;
    if (!sharing) {
      // Chưa đồng ý: "Bật chia sẻ vị trí"; GPS tắt / chưa có quyền: nút sửa đúng chỗ
      text = gate == LocationGate.noConsent || gate == LocationGate.checking
          ? t('location.action.turnOn')
          : locationGateAction(gate);
      icon = gate == LocationGate.noConsent ? Icons.power_settings_new_rounded : Icons.location_off_outlined;
      iconBackground = Colors.white.withValues(alpha: 0.16);
      onTap = onTurnOn;
    } else if (featured != null) {
      text = nextActionText(featured!) ?? t('home.openTrip');
      icon = Icons.navigation_rounded;
      iconBackground = AppColors.orange;
      onTap = () => onOpenTrip(featured!);
    } else {
      // Đã đồng ý nhưng không có chuyến đang chạy: không cần nút, chỉ để dòng trạng thái nói
      return const SizedBox.shrink();
    }

    return Semantics(
      button: true,
      label: text,
      excludeSemantics: true,
      child: Material(
        color: AppColors.navy,
        shape: const StadiumBorder(),
        elevation: 0,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: 52,
            constraints: const BoxConstraints(maxWidth: 300),
            padding: const EdgeInsets.fromLTRB(7, 7, 22, 7),
            decoration: const ShapeDecoration(
              shape: StadiumBorder(),
              shadows: <BoxShadow>[BoxShadow(color: Color(0x590C2858), blurRadius: 28, offset: Offset(0, 10))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: iconBackground, shape: BoxShape.circle),
                  child: Icon(icon, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Thanh kính nổi trên sheet: trạng thái chia sẻ vị trí + công tắc iOS bật / tắt thẳng tại chỗ.
/// Đang làm chuyến thì công tắc khóa (luật công ty: không tắt định vị khi đang làm đơn).
class _StatusLine extends StatelessWidget {
  final LocationGate gate;
  final TrackerState tracker;
  final bool locked;
  final bool busy;
  final ValueChanged<bool> onChanged;

  const _StatusLine({
    required this.gate,
    required this.tracker,
    required this.locked,
    required this.busy,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    String text;
    String? detail;
    Color tint;
    IconData icon;
    bool on;
    if (gate == LocationGate.noConsent) {
      text = t('location.status.off');
      detail = t('location.status.offDetail');
      tint = const Color(0xFF8E8E93);
      icon = CupertinoIcons.location_slash_fill;
      on = false;
    } else if (gate == LocationGate.checking) {
      text = t('location.gate.checking');
      tint = const Color(0xFF8E8E93);
      icon = CupertinoIcons.location;
      on = false;
    } else if (gate != LocationGate.ready) {
      // Đã đồng ý nhưng GPS tắt / chưa có quyền: công tắc tắt, gạt lên để sửa
      text = locationGateText(gate);
      tint = IosColors.red;
      icon = CupertinoIcons.location_slash_fill;
      on = false;
    } else if (tracker.running && tracker.offline && tracker.pending > 0) {
      text = t('location.status.offlineTitle');
      detail = t('location.status.offlineDetail', <String, Object?>{'count': tracker.pending});
      tint = IosColors.orange;
      icon = CupertinoIcons.location_fill;
      on = true;
    } else {
      final DateTime? sent = tracker.lastSentAt;
      text = t('location.status.sharing');
      detail = tracker.running && sent != null
          ? t('location.status.updatedAt', <String, Object?>{'time': clock(sent)})
          : (locked ? t('location.status.locked') : null);
      tint = IosColors.green;
      icon = CupertinoIcons.location_fill;
      on = true;
    }

    final Widget control = busy || gate == LocationGate.checking
        ? const SizedBox(width: 51, child: Center(child: CupertinoActivityIndicator()))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (locked && on)
                Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(CupertinoIcons.lock_fill, size: 14, color: IosColors.tertiaryLabel),
                ),
              AdaptiveSwitch(
                value: on,
                activeColor: IosColors.green,
                onChanged: locked && on ? null : onChanged,
              ),
            ],
          );

    return Semantics(
      container: true,
      label: detail == null ? text : '$text. $detail',
      child: Glass(
        nativeSurface: true,
        borderRadius: BorderRadius.circular(26),
        opacity: 0.72,
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: tint.withValues(alpha: 0.14), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Icon(icon, size: 18, color: tint),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text),
                  ),
                  if (detail != null)
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: IosColors.secondaryLabel),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            control,
          ],
        ),
      ),
    );
  }
}

class _QuickTiles extends StatelessWidget {
  final VoidCallback onTrips;
  final VoidCallback onPhotos;
  final VoidCallback onBreakdown;
  final VoidCallback onNavigate;
  final VoidCallback onMore;

  const _QuickTiles({
    required this.onTrips,
    required this.onPhotos,
    required this.onBreakdown,
    required this.onNavigate,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        GlassActionButton(icon: CupertinoIcons.list_bullet, label: t('home.action.trips'), onTap: onTrips),
        GlassActionButton(icon: CupertinoIcons.camera, label: t('home.action.photos'), onTap: onPhotos),
        GlassActionButton(
          icon: CupertinoIcons.exclamationmark_triangle,
          label: t('home.action.breakdown'),
          onTap: onBreakdown,
          color: GlassActionButton.danger,
        ),
        GlassActionButton(icon: CupertinoIcons.location_north, label: t('common.navigate'), onTap: onNavigate),
      ],
    );
  }
}
