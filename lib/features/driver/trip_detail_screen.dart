// T2–T4, T8: chuyến đang chạy trên bản đồ (canvas TX-ChuyenDangChay).
// Bản đồ các điểm + sheet kính: từng điểm với mốc đã bấm, gọi, dẫn đường; hoàn tác; "Đến điểm khác?";
// ô đồng hồ km / giờ máy khi rời điểm trả cuối; ảnh, biên bản; báo hỏng. Đáy màn: vuốt để xác nhận mốc.
// Nghiệp vụ theo web (src/features/driver/TripCard.tsx) và doc slice D mục 2–4.
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:vietmap_flutter_gl/vietmap_flutter_gl.dart' show LatLng;
import 'package:uuid/uuid.dart';

import '../../core/api/call.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/ios.dart';
import 'directions_logic.dart';
import 'driver_api.dart';
import 'driver_providers.dart';
import 'driver_widgets.dart';
import 'location_gate.dart';
import 'location_tracker.dart';
import 'slide_to_confirm.dart';
import 'trip_logic.dart';
import 'trip_map.dart';

// Lỗi chỉ cần tải lại chuyến (người cùng tổ lái bấm trước, thứ tự đổi, đổi tổ lái): không báo lỗi to
const List<String> reloadCodes = <String>[
  'MILESTONE_ALREADY_RECORDED',
  'MILESTONE_OUT_OF_ORDER',
  'STOP_NOT_ON_TRIP',
  'DISPATCH_TRIP_NOT_FOUND',
  'MILESTONE_NOT_FOUND',
];

/// Vị trí một lần để gửi kèm mốc / ảnh. Không được phép, GPS tắt hay quá 8 giây thì null:
/// mốc vẫn gửi, chỉ không kèm vị trí (tài xế không bị kẹt vì GPS yếu).
Future<Position?> currentPositionOrNull() async {
  try {
    final LocationPermission permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) {
      return null;
    }
    final Position? last = await Geolocator.getLastKnownPosition();
    if (last != null && DateTime.now().difference(last.timestamp).inSeconds <= 30) {
      return last;
    }
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)),
    );
  } catch (_) {
    return null;
  }
}

/// Thẻ chỉ đường trên bản đồ: chỗ rẽ tiếp theo và quãng đường còn lại. Xe chưa ở trên tuyến và chưa có tuyến
/// từ vị trí xe ([goToStop] khác null) thì chỉ nhắc đi tới điểm đó, không báo rẽ theo một tuyến xe chưa vào.
class _DirectionsCard extends StatelessWidget {
  final RouteTrack track;
  final int destinationNumber;
  final Position? position;
  final VoidCallback onExit;
  // Tuyến từ vị trí xe có thời gian; tuyến đã lưu thì null
  final double? durationMinutes;
  final int? goToStop;
  // Chưa có tuyến xe tải từ chỗ xe: gợi ý mở Google Maps tới điểm đó (có cảnh báo tuyến xe con trước khi mở)
  final VoidCallback? onOpenMaps;

  const _DirectionsCard({
    this.onOpenMaps,
    required this.track,
    required this.destinationNumber,
    required this.position,
    required this.onExit,
    this.durationMinutes,
    this.goToStop,
  });

  static String distanceText(double meters) {
    if (meters < 1000) {
      return '${(meters / 10).round() * 10} m';
    }
    return '${(meters / 1000).toStringAsFixed(1).replaceAll('.', I18n.lang == 'vi' ? ',' : '.')} km';
  }

  static String durationText(double minutes) {
    final int total = minutes.ceil();
    if (total < 60) {
      return t('directions.minutes', <String, Object?>{'minutes': total});
    }
    return t('directions.hoursMinutes', <String, Object?>{'hours': total ~/ 60, 'minutes': total % 60});
  }

  static (IconData, String) turnLook(TurnKind turn) {
    return switch (turn) {
      TurnKind.straight => (CupertinoIcons.arrow_up, t('directions.turn.straight')),
      TurnKind.slightLeft => (CupertinoIcons.arrow_up_left, t('directions.turn.slightLeft')),
      TurnKind.left => (CupertinoIcons.arrow_turn_up_left, t('directions.turn.left')),
      TurnKind.sharpLeft => (CupertinoIcons.arrow_turn_up_left, t('directions.turn.sharpLeft')),
      TurnKind.slightRight => (CupertinoIcons.arrow_up_right, t('directions.turn.slightRight')),
      TurnKind.right => (CupertinoIcons.arrow_turn_up_right, t('directions.turn.right')),
      TurnKind.sharpRight => (CupertinoIcons.arrow_turn_up_right, t('directions.turn.sharpRight')),
      TurnKind.uTurn => (CupertinoIcons.arrow_uturn_left, t('directions.turn.uTurn')),
    };
  }

  @override
  Widget build(BuildContext context) {
    final Position? here = position;
    final RouteProgress progress = here == null
        ? RouteProgress(segment: 0, offRouteM: 0, remainingM: track.totalM)
        : track.progress(LatLng(here.latitude, here.longitude));
    final NextManeuver next = track.nextManeuver(progress);
    final TurnKind? turn = next.turn;
    final int? goTo = goToStop;
    final (IconData, String) look = goTo != null
        ? (Icons.navigation_rounded, t('directions.goToStop', <String, Object?>{'number': goTo}))
        : turn == null
            ? (CupertinoIcons.flag_fill, t('directions.arrive', <String, Object?>{'number': destinationNumber}))
            : turnLook(turn);
    final double? minutes = durationMinutes;
    final String title = goTo != null ? look.$2 : '${t('directions.in', <String, Object?>{'distance': distanceText(next.distanceM)})} · ${look.$2}';
    final String detail = goTo != null
        ? t('directions.noRouteFromHere')
        : minutes != null && track.totalM > 0
            ? t('directions.remainingTime', <String, Object?>{
                'distance': distanceText(progress.remainingM),
                'time': durationText(minutes * progress.remainingM / track.totalM),
              })
            : t('directions.remaining', <String, Object?>{'distance': distanceText(progress.remainingM)});

    return Glass(
      borderRadius: BorderRadius.circular(24),
      opacity: 0.9,
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      child: Row(
        children: <Widget>[
          IosIconBadge(icon: look.$1, color: AppColors.navy, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text),
                ),
                if (goTo == null && (next.road ?? '').isNotEmpty)
                  Text(
                    next.road!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.label),
                  ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
                if (goTo != null && onOpenMaps != null) ...<Widget>[
                  const SizedBox(height: 8),
                  _GoogleMapsButton(onPressed: onOpenMaps!),
                ],
              ],
            ),
          ),
          Semantics(
            button: true,
            label: t('directions.exit'),
            excludeSemantics: true,
            child: IconButton(
              onPressed: onExit,
              icon: Icon(CupertinoIcons.xmark_circle_fill, color: IosColors.secondaryLabel, size: 28),
            ),
          ),
        ],
      ),
    );
  }
}

/// Nút mở Google Maps mang màu của Google Maps: ghim nhiều màu như logo, chữ và nền xanh Google
class _GoogleMapsButton extends StatelessWidget {
  static const Color blue = Color(0xFF1A73E8);

  final VoidCallback onPressed;

  const _GoogleMapsButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      minimumSize: const Size(44, 42),
      color: blue.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(999),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (Rect bounds) => const SweepGradient(
              startAngle: 0,
              endAngle: 6.2832,
              transform: GradientRotation(-0.6),
              colors: <Color>[
                Color(0xFF4285F4),
                Color(0xFF34A853),
                Color(0xFF34A853),
                Color(0xFFFBBC04),
                Color(0xFFEA4335),
                Color(0xFF4285F4),
              ],
            ).createShader(bounds),
            child: const Icon(Icons.location_on, size: 21, color: Colors.white),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              t('directions.openGoogleMaps'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: blue),
            ),
          ),
        ],
      ),
    );
  }
}

class TripDetailScreen extends ConsumerStatefulWidget {
  final String tripId;

  const TripDetailScreen({super.key, required this.tripId});

  @override
  ConsumerState<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends ConsumerState<TripDetailScreen> {
  // Chuyến server trả sau khi bấm mốc / hoàn tác: vẽ ngay, không đợi tải lại danh sách
  MyTrip? updated;
  bool busy = false;
  // Một Idempotency-Key cho mỗi mốc ("điểm|loại"); mạng lỗi bấm lại thì giữ nguyên để server không ghi hai lần
  final Map<String, String> keys = <String, String>{};
  final TextEditingController kmController = TextEditingController();
  final TextEditingController hoursController = TextEditingController();
  String? meterError;

  // Chỉ đường, có khi tài xế bấm bắt đầu, tắt khi tới điểm hoặc bấm thoát. Xe trên tuyến đã lưu của đơn thì đi theo tuyến đó,
  // không tốn lượt Vietmap. Xe ở xa thì xin tuyến từ vị trí xe tới điểm kế; không có đường (xe nặng, đường cấm) thì vẫn
  // hiện tuyến đã lưu và nhắc đi tới điểm, không đổi sang tuyến ô tô.
  static const double sheetNavigating = 0.28;
  static const Duration liveRetryGap = Duration(minutes: 5);
  final DraggableScrollableController sheet = DraggableScrollableController();
  int? directionsStop;
  RouteTrack? track;
  RouteTrack? liveTrack;
  double? liveDurationMinutes;
  RerouteGate rerouteGate = RerouteGate();
  DateTime? liveRetryAt;
  bool loadingDirections = false;
  bool requestingLive = false;
  Position? navPosition;
  StreamSubscription<Position>? navPositions;
  // Tuyến đã lưu của đơn đã giải mã: chỉ giải mã lại khi đổi, tuyến dài có hàng nghìn điểm
  String? savedRouteEncoded;
  List<LatLng>? savedRoute;

  List<LatLng>? savedRouteOf(MyTrip trip) {
    final String? encoded = trip.routePolyline;
    if (encoded != savedRouteEncoded) {
      savedRouteEncoded = encoded;
      savedRoute = (encoded ?? '').isEmpty ? null : decodePolyline(encoded!);
    }
    return savedRoute;
  }

  Future<void> startDirections(MyTrip trip, int stopSequence) async {
    setState(() => loadingDirections = true);
    final Position? position = await currentPositionOrNull();
    if (!mounted) return;
    final List<LatLng>? route = savedRouteOf(trip);
    final bool hasSaved = route != null && route.length >= 2;
    // Không có tuyến đã lưu và cũng không biết xe ở đâu thì không có gì để chỉ
    if (!hasSaved && position == null) {
      setState(() => loadingDirections = false);
      snack(t('directions.noRoute'));
      return;
    }
    HapticFeedback.mediumImpact();
    rerouteGate = RerouteGate();
    liveRetryAt = null;
    setState(() {
      directionsStop = stopSequence;
      track = hasSaved ? RouteTrack(route) : null;
      liveTrack = null;
      liveDurationMinutes = null;
      navPosition = position;
    });
    await navPositions?.cancel();
    navPositions = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
    ).listen((Position next) => onNavPosition(trip, next), onError: (Object _) {});
    if (sheet.isAttached) {
      sheet.animateTo(sheetNavigating, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    }
    if (position != null) {
      await considerLiveRoute(trip, position);
    }
    if (mounted) setState(() => loadingDirections = false);
    // Không có tuyến đã lưu mà cũng không lấy được tuyến từ vị trí xe
    if (mounted && directionsStop != null && track == null && liveTrack == null) {
      snack(t('directions.noRoute'));
      stopDirections();
    }
  }

  void onNavPosition(MyTrip trip, Position position) {
    if (!mounted || directionsStop == null) return;
    setState(() => navPosition = position);
    unawaited(considerLiveRoute(trip, position));
  }

  /// Quyết định có xin tuyến từ vị trí xe không. App ẩn thì không tốn lượt.
  Future<void> considerLiveRoute(MyTrip trip, Position position) async {
    if (requestingLive) return;
    final AppLifecycleState? lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    final LatLng here = LatLng(position.latitude, position.longitude);
    final DateTime now = DateTime.now();
    final RouteTrack? live = liveTrack;
    final RouteTrack? saved = track;
    final bool wanted = live != null
        ? rerouteGate.shouldReroute(offRouteM: live.progress(here).offRouteM, accuracyM: position.accuracy, now: now)
        : wantsLiveRoute(
            offRouteM: saved?.progress(here).offRouteM ?? double.infinity,
            accuracyM: position.accuracy,
            now: now,
            retryAt: liveRetryAt,
          );
    if (!wanted) return;

    requestingLive = true;
    rerouteGate.markRequested(now);
    final int? stop = directionsStop;
    try {
      final TripDirections result = await fetchTripDirections(trip.publicId, position.latitude, position.longitude);
      if (!mounted || directionsStop != stop || stop == null) return;
      setState(() {
        liveTrack = RouteTrack(
          decodePolyline(result.polyline),
          stepRoads: <int, String?>{for (final DirectionStep step in result.steps) step.pointIndex: step.road},
        );
        liveDurationMinutes = result.durationMinutes;
      });
    } catch (_) {
      // Không có đường cho xe này, hết lượt, mất mạng: giữ tuyến đang có, thử lại sau vì mỗi lần thử có thể tốn lượt
      liveRetryAt = now.add(liveRetryGap);
    } finally {
      requestingLive = false;
    }
  }

  void stopDirections() {
    navPositions?.cancel();
    navPositions = null;
    if (!mounted) return;
    setState(() {
      directionsStop = null;
      track = null;
      liveTrack = null;
      liveDurationMinutes = null;
      navPosition = null;
    });
  }

  @override
  void initState() {
    super.initState();
    // Danh sách tải xong bản mới thì bỏ bản tạm, dùng dữ liệu server
    ref.listenManual<AsyncValue<List<MyTrip>>>(driverTripsProvider,
        (AsyncValue<List<MyTrip>>? previous, AsyncValue<List<MyTrip>> next) {
      if (next is AsyncData<List<MyTrip>> && updated != null && mounted) {
        setState(() {
          updated = null;
        });
      }
    });
  }

  @override
  void dispose() {
    navPositions?.cancel();
    sheet.dispose();
    kmController.dispose();
    hoursController.dispose();
    super.dispose();
  }

  void snack(String text, {bool isError = true}) {
    showIosToast(context, text, isError: isError);
  }

  void reload() {
    ref.invalidate(driverTripsProvider);
  }

  void applyUpdated(MyTrip trip) {
    setState(() {
      updated = trip;
    });
    reload();
  }

  bool get sharesLocation => ref.read(consentProvider).value?.accepted ?? false;

  Future<void> record(MyTrip trip, int stopSequence, String kind) async {
    final String id = '$stopSequence|$kind';
    final TripStop? stop = trip.stopAt(stopSequence);

    // BR-TRK-009: km có dấu chấm nghìn ("125.430"); giờ máy nhận số lẻ ("1250,5")
    final ({bool km, bool hours})? meters = meterFields(trip);
    final bool withMeters = meters != null && kind == 'Departed' && stopSequence == trip.nextAction?.stopSequence;
    int? odometerKm;
    double? engineHours;
    if (withMeters && meters != null) {
      final String kmText = kmController.text.trim();
      final String hoursText = hoursController.text.trim();
      if (meters.km && kmText.isNotEmpty) {
        odometerKm = int.tryParse(kmText.replaceAll(RegExp(r'[.\s]'), ''));
        if (odometerKm == null) {
          setState(() => meterError = t('tripDetail.meter.kmInvalid'));
          return;
        }
      }
      if (meters.hours && hoursText.isNotEmpty) {
        engineHours = double.tryParse(hoursText.replaceAll(' ', '').replaceAll(',', '.'));
        if (engineHours == null) {
          setState(() => meterError = t('tripDetail.meter.hoursInvalid'));
          return;
        }
      }
    }

    // Luật công ty: mốc nào cũng phải có vị trí thật
    if (ref.read(locationGateProvider) != LocationGate.ready) {
      await ref.read(locationGateProvider.notifier).check();
      return;
    }
    keys.putIfAbsent(id, () => const Uuid().v4());
    setState(() {
      busy = true;
    });
    try {
      final Position? position = await currentPositionOrNull();
      if (position == null) {
        if (mounted) {
          snack(t('tripDetail.noLocation'));
        }
        return;
      }
      final MyTrip result = await recordMilestone(
        trip.publicId,
        MilestoneRequest(
          stopSequence: stopSequence,
          kind: kind,
          idempotencyKey: keys[id],
          latitude: position?.latitude,
          longitude: position?.longitude,
          accuracyM: position?.accuracy.roundToDouble(),
          odometerKm: odometerKm,
          engineHours: engineHours,
        ),
      );
      keys.remove(id);
      HapticFeedback.mediumImpact();
      kmController.clear();
      hoursController.clear();
      meterError = null;
      applyUpdated(result);
      // Vừa bấm mốc thì gửi vị trí luôn, điều phối thấy ngay
      ref.read(locationTrackerProvider.notifier).flush();
      if (mounted) {
        snack(t('tripDetail.milestoneRecorded', <String, Object?>{'milestone': milestoneDoneLabel(kind, stop?.kind ?? 'Via'), 'time': clock(DateTime.now())}), isError: false);
      }
      // Vừa dỡ hàng / vừa xong chuyến: hỏi chụp biên bản và ảnh hiện trường ngay
      if (mounted && docsDue(result) && (kind == 'Unloaded' || result.nextAction == null)) {
        await askForDocuments(result);
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      if (reloadCodes.contains(error.code)) {
        keys.remove(id);
        snack(t('tripDetail.tripUpdated'), isError: false);
        setState(() => updated = null);
        reload();
      } else if (error.code == 'METER_READING_INVALID' || error.code == 'METER_NOT_ALLOWED') {
        // Sửa số rồi vuốt lại là một lần bấm mới: bỏ key cũ để server không trả lại đúng lỗi này
        keys.remove(id);
        setState(() => meterError = error.message);
      } else if (error.code == 'INVALID_RECORDED_AT') {
        snack(t('tripDetail.clockOff'));
      } else if (error.status == null) {
        // Mất mạng: giữ key, vuốt lại sẽ không bị ghi hai lần
        snack(t('tripDetail.offline'));
      } else {
        snack(error.message);
        if (error.code == 'TRIP_NOT_EDITABLE') reload();
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  Future<void> askForDocuments(MyTrip trip) async {
    List<TripDocument> docs = const <TripDocument>[];
    try {
      docs = await ref.read(tripDocumentsProvider(trip.publicId).future);
    } catch (_) {}
    final ({int field, int pod}) counts = docCounts(docs);
    if (!mounted || (counts.field > 0 && counts.pod > 0)) return;
    final bool finished = trip.nextAction == null;
    final bool go = await showIosConfirm(
      context,
      title: finished ? t('tripDetail.docsPrompt.titleFinished') : t('tripDetail.docsPrompt.titleUnloaded'),
      message: t('tripDetail.docsPrompt.message'),
      action: t('tripDetail.docsPrompt.action'),
      cancel: t('common.notNow'),
      destructive: false,
    );
    if (go && mounted) {
      context.push('/driver/trips/${trip.publicId}/documents');
    }
  }

  Future<void> confirmUndo(MyTrip trip, TripMilestone milestone) async {
    final TripStop? stop = trip.stopAt(milestone.stopSequence);
    final String text = undoKeepsOrderInProgress(trip, milestone)
        ? t('tripDetail.undo.keepsInProgress')
        : t('tripDetail.undo.message');
    final bool ok = await showIosConfirm(
      context,
      title: t('tripDetail.undo.title', <String, Object?>{'milestone': milestoneDoneLabel(milestone.kind, stop?.kind ?? 'Via')}),
      message: text,
      action: t('tripDetail.undo.action'),
    );
    if (!ok || !mounted) return;
    setState(() => busy = true);
    try {
      applyUpdated(await undoMilestone(trip.publicId, milestone.publicId));
    } on ApiException catch (error) {
      if (!mounted) return;
      snack(error.message);
      if (reloadCodes.contains(error.code) ||
          error.code == 'MILESTONE_UNDO_EXPIRED' ||
          error.code == 'MILESTONE_NOT_LAST') {
        setState(() => updated = null);
        reload();
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// "Đến điểm khác?": khách đổi thứ tự điểm, đánh dấu đã tới một điểm chưa làm
  Future<void> pickOtherStop(MyTrip trip) async {
    final List<TripStop> stops = skippableStops(trip);
    final TripStop? picked = await showIosActionSheet<TripStop>(
      context,
      title: t('tripDetail.otherStop.title'),
      message: t('tripDetail.otherStop.message'),
      options: <IosSheetOption<TripStop>>[
        for (final TripStop stop in stops)
          IosSheetOption<TripStop>(stop, '${stop.sequence}. ${tEnum('stopKind', stop.kind)} · ${stop.address}'),
      ],
    );
    if (picked != null && mounted) {
      await record(trip, picked.sequence, 'Arrived');
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<MyTrip>> tripsValue = ref.watch(driverTripsProvider);
    MyTrip? trip = updated;
    if (trip == null) {
      for (final MyTrip candidate in tripsValue.value ?? const <MyTrip>[]) {
        if (candidate.publicId == widget.tripId) trip = candidate;
      }
    }

    if (trip == null) {
      return Scaffold(
        appBar: AppBar(title: Text(t('tripDetail.title'))),
        body: tripsValue.isLoading
            ? const Center(child: CupertinoActivityIndicator(radius: 14))
            : tripsValue.hasError
                ? ErrorView(message: errorMessage(tripsValue.error!), onRetry: reload)
                : EmptyView(text: t('tripDetail.notFound')),
      );
    }
    return _buildTrip(context, trip);
  }

  Widget _buildTrip(BuildContext context, MyTrip trip) {
    final MediaQueryData media = MediaQuery.of(context);
    final TrackerState tracker = ref.watch(locationTrackerProvider);
    final Position? position = navPosition ?? tracker.lastPosition ?? ref.watch(myPositionProvider).value;
    final NextAction? next = trip.nextAction;
    final TripStop? nextStop = next == null ? null : trip.stopAt(next.stopSequence);
    final String? blocked = milestoneBlockedText(trip, DateTime.now());
    final LocationGate gate = ref.watch(locationGateProvider);
    final bool needsLocation = blocked == null && next != null && gate != LocationGate.ready;

    // Xe đang đi tới một điểm có tọa độ thì mới có chỉ đường
    final bool headingToStop = trip.trackingActive && next?.kind == 'Arrived' && (nextStop?.hasCoordinates ?? false);
    // Đã tới điểm (mình hay người cùng tổ lái bấm) thì tắt chỉ đường; rời điểm thì nút hiện lại cho điểm kế
    if (directionsStop != null && !(headingToStop && next?.stopSequence == directionsStop)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => stopDirections());
    }
    // Có tuyến từ vị trí xe thì đi theo tuyến đó, không thì theo tuyến đã lưu
    final RouteTrack? activeTrack = liveTrack ?? track;
    final bool navigating = activeTrack != null && headingToStop && next?.stopSequence == directionsStop;
    // Xe đang ở trên tuyến thì bám theo xe; đang ở xa thì xem cả tuyến
    final bool onRoute = navigating &&
        position != null &&
        activeTrack.progress(LatLng(position.latitude, position.longitude)).offRouteM <= offSavedRouteM;

    return Scaffold(
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: TripMap(
              stops: trip.stops,
              me: position == null ? null : LatLng(position.latitude, position.longitude),
              focusSequence: next?.stopSequence,
              route: navigating ? activeTrack.points : savedRouteOf(trip),
              follow: onRoute,
              fitPadding: navigating
                  // Thẻ "Hãy đi tới điểm" có thêm nút nên cao hơn, chừa thêm chỗ để không đè lên điểm dừng
                  ? EdgeInsets.fromLTRB(48, media.padding.top + (liveTrack == null && !onRoute ? 300 : 220), 48, media.size.height * sheetNavigating + 110)
                  : EdgeInsets.fromLTRB(48, media.padding.top + 130, 48, media.size.height * 0.5 + 40),
            ),
          ),
          // Mép trên bản đồ mờ dần sau các viên kính (progressive blur), như Apple Maps
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: ProgressiveBlur(height: media.padding.top + 80, maxSigma: 8, tintOpacity: 0.25),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: media.padding.top + 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    IosBackButton(size: 52, onPressed: () => context.pop()),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Glass(
                        nativeSurface: true,
                        borderRadius: BorderRadius.circular(26),
                        opacity: 0.66,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('${tripTimeText(trip)} · ${trip.orderCode}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
                            Text(trip.customerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const MapStyleButton(size: 52),
                  ],
                ),
                const SizedBox(height: 10),
                if (navigating)
                  _DirectionsCard(
                    track: activeTrack,
                    // Tuyến từ vị trí xe kết thúc ở điểm kế; tuyến đã lưu kết thúc ở điểm cuối
                    destinationNumber: liveTrack != null || trip.stops.isEmpty ? next!.stopSequence : trip.stops.last.sequence,
                    durationMinutes: liveTrack != null ? liveDurationMinutes : null,
                    goToStop: liveTrack == null && position != null && !onRoute ? next!.stopSequence : null,
                    onOpenMaps: nextStop == null ? null : () => navigateTo(context, nextStop),
                    position: position,
                    onExit: stopDirections,
                  )
                else ...<Widget>[
                  const SharingChip(),
                  if (headingToStop && blocked == null && !needsLocation) ...<Widget>[
                    const SizedBox(height: 10),
                    IosPillButton(
                      label: t('directions.start'),
                      icon: CupertinoIcons.location_north_fill,
                      busy: loadingDirections,
                      onPressed: () => startDirections(trip, next!.stopSequence),
                    ),
                  ],
                ],
              ],
            ),
          ),
          DraggableScrollableSheet(
            controller: sheet,
            initialChildSize: 0.5,
            minChildSize: 0.28,
            maxChildSize: 0.92,
            snap: true,
            snapSizes: const <double>[0.5],
            builder: (BuildContext context, ScrollController scroll) {
              return Glass(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                opacity: 0.66,
                child: ColoredBox(
                  color: IosColors.groupedBackground.withValues(alpha: 0.18),
                  child: ListView(
                    controller: scroll,
                    padding: EdgeInsets.fromLTRB(16, 0, 16, media.padding.bottom + 110),
                    children: _sheetChildren(trip, nextStop),
                  ),
                ),
              );
            },
          ),
          // Đáy màn: vuốt xác nhận mốc, hoặc câu vì sao chưa bấm được
          Positioned(
            left: 16,
            right: 16,
            bottom: media.padding.bottom + 16,
            child: needsLocation
                ? _LocationRequiredPanel(gate: gate)
                : (blocked != null || next == null)
                ? Glass(
                    borderRadius: BorderRadius.circular(22),
                    opacity: 0.85,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: <Widget>[
                        IosIconBadge(
                          icon: trip.nextAction == null ? CupertinoIcons.checkmark_alt : CupertinoIcons.clock_fill,
                          color: trip.nextAction == null ? IosColors.green : const Color(0xFF8E8E93),
                          size: 32,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(blocked ?? '',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: trip.nextAction == null ? AppColors.okText : AppColors.label)),
                        ),
                      ],
                    ),
                  )
                // Thanh vuốt ngắn, căn giữa (như "slide to answer" của iPhone)
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: SlideToConfirm(
                        key: ValueKey<String>('${next.stopSequence}|${next.kind}'),
                        label: milestoneActionLabel(next.kind, nextStop?.kind ?? 'Via'),
                        enabled: !busy,
                        onConfirmed: () => record(trip, next.stopSequence, next.kind),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _sheetChildren(MyTrip trip, TripStop? nextStop) {
    final List<Widget> children = <Widget>[const SheetGrabber()];
    // Đã dỡ hàng / xong chuyến: nhắc chụp ảnh hiện trường và biên bản ngay đầu sheet
    if (docsDue(trip)) {
      children.add(DocsReminderCard(trip: trip, showWhenDone: true));
    }
    final NextAction? next = trip.nextAction;
    final bool canRecord = trip.trackingActive && next != null;

    // Các điểm
    for (final TripStop stop in trip.stops) {
      children.add(_StopCard(
        trip: trip,
        stop: stop,
        isCurrent: stop.sequence == next?.stopSequence,
        sharesLocation: sharesLocation,
      ));
      children.add(const SizedBox(height: 10));
    }

    // Hoàn tác, đến điểm khác
    final TripMilestone? undoable = undoableMilestone(trip);
    final List<TripStop> skippable = canRecord ? skippableStops(trip) : const <TripStop>[];
    if (undoable != null || skippable.isNotEmpty) {
      final TripStop? undoStop = undoable == null ? null : trip.stopAt(undoable.stopSequence);
      children.add(Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          if (undoable != null)
            _TintButton(
              icon: CupertinoIcons.arrow_uturn_left,
              text: t('tripDetail.undo.button', <String, Object?>{'milestone': milestoneDoneLabel(undoable.kind, undoStop?.kind ?? 'Via')}),
              color: IosColors.orange,
              onPressed: busy ? null : () => confirmUndo(trip, undoable),
            ),
          if (skippable.isNotEmpty)
            _TintButton(
              icon: CupertinoIcons.arrow_branch,
              text: t('tripDetail.otherStop.button'),
              color: IosColors.blue,
              onPressed: busy ? null : () => pickOtherStop(trip),
            ),
        ],
      ));
      children.add(const SizedBox(height: 12));
    }

    // Ô đồng hồ khi rời điểm trả cuối (lái chính)
    final ({bool km, bool hours})? meters = canRecord ? meterFields(trip) : null;
    if (meters != null) {
      children.add(_MeterInputs(
        km: meters.km,
        hours: meters.hours,
        kmController: kmController,
        hoursController: hoursController,
        error: meterError,
        onChanged: () {
          if (meterError != null) setState(() => meterError = null);
        },
      ));
      children.add(const SizedBox(height: 10));
    }

    // Việc nhanh
    children.add(const SizedBox(height: 4));
    children.add(Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        GlassActionButton(
          icon: CupertinoIcons.phone,
          label: nextStop?.contactName == null ? t('common.call') : t('tripDetail.callName', <String, Object?>{'name': nextStop!.contactName}),
          onTap: (nextStop?.contactPhone ?? '').isEmpty ? null : () => callPhone(context, nextStop!.contactPhone),
        ),
        GlassActionButton(
          icon: CupertinoIcons.location_north,
          label: t('common.navigate'),
          onTap: nextStop == null ? null : () => navigateTo(context, nextStop),
        ),
        GlassActionButton(
          icon: CupertinoIcons.camera,
          label: t('tripDetail.action.documents'),
          onTap: () => context.push('/driver/trips/${trip.publicId}/documents'),
        ),
        GlassActionButton(
          icon: CupertinoIcons.exclamationmark_triangle,
          label: t('tripDetail.action.breakdown'),
          color: GlassActionButton.danger,
          onTap: trip.vehicles.isEmpty ? null : () => context.push('/driver/trips/${trip.publicId}/breakdown'),
        ),
      ],
    ));

    // Thông tin chuyến (không có giá tiền)
    children.add(const SizedBox(height: 14));
    children.add(_TripInfo(trip: trip));
    children.add(const MapAttribution());
    return children;
  }
}

class _StopBadge extends StatelessWidget {
  final TripStop stop;

  const _StopBadge({required this.stop});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(color: stopColor(stop.kind), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text('${stop.sequence}',
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

class _StopCard extends StatelessWidget {
  final MyTrip trip;
  final TripStop stop;
  final bool isCurrent;
  final bool sharesLocation;

  const _StopCard({required this.trip, required this.stop, required this.isCurrent, required this.sharesLocation});

  @override
  Widget build(BuildContext context) {
    final StopState state = stopState(trip, stop);
    final String? nextStep = trip.trackingActive ? nextStepAtStop(trip, stop) : null;

    final List<Widget> lines = <Widget>[];
    for (final String step in stepsForStop(stop.kind)) {
      final TripMilestone? done = milestoneOf(trip, stop.sequence, step);
      final bool isNext = isCurrent && step == trip.nextAction?.kind;
      if (done == null && !isCurrent) continue;
      lines.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: <Widget>[
            if (done != null)
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(color: IosColors.green, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, size: 15, color: Colors.white),
              )
            else
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: isNext ? AppColors.navy : AppColors.control, width: 2),
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                done != null
                    ? '${milestoneDoneLabel(step, stop.kind)} · ${clock(done.receivedAt)}'
                    : milestoneActionLabel(step, stop.kind),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isNext ? FontWeight.w600 : FontWeight.w400,
                  color: done != null ? AppColors.text : (isNext ? AppColors.navy : IosColors.secondaryLabel),
                ),
              ),
            ),
            if (isNext) IosPill(t('tripDetail.next'), color: IosColors.orange),
          ],
        ),
      ));
    }
    if (!isCurrent && state == StopState.todo && nextStep != null) {
      lines.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(t('tripDetail.notArrived'), style: TextStyle(fontSize: 14, color: IosColors.secondaryLabel)),
      ));
    }

    final String contact = <String>[
      if ((stop.contactName ?? '').isNotEmpty) stop.contactName!,
      if ((stop.contactPhone ?? '').isNotEmpty) stop.contactPhone!,
    ].join(' · ');

    return Opacity(
      opacity: state == StopState.done && !isCurrent ? 0.7 : 1,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: isCurrent ? Border.all(color: AppColors.navy, width: 2) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _StopBadge(stop: stop),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(stopKindTitle(stop.kind).toUpperCase(),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                              color: stop.kind == 'Delivery' ? AppColors.warmText : AppColors.navy)),
                      Text(stop.address,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
                      if (contact.isNotEmpty)
                        Text(contact, style: TextStyle(fontSize: 14, color: IosColors.secondaryLabel)),
                      if ((stop.note ?? '').isNotEmpty)
                        Text(stop.note!, style: TextStyle(fontSize: 14, color: IosColors.secondaryLabel)),
                    ],
                  ),
                ),
                if (state == StopState.done)
                  Icon(CupertinoIcons.checkmark_circle_fill, color: IosColors.green, size: 24),
              ],
            ),
            ...lines,
            if (!(state == StopState.done && !isCurrent)) ...<Widget>[
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  if ((stop.contactPhone ?? '').isNotEmpty)
                    Expanded(
                      child: _TintButton(
                        icon: CupertinoIcons.phone_fill,
                        text: t('common.call'),
                        color: IosColors.green,
                        expand: true,
                        onPressed: () => callPhone(context, stop.contactPhone),
                      ),
                    ),
                  if ((stop.contactPhone ?? '').isNotEmpty) const SizedBox(width: 8),
                  Expanded(
                    child: _TintButton(
                      icon: CupertinoIcons.location_north_fill,
                      text: t('common.navigate'),
                      color: IosColors.blue,
                      expand: true,
                      onPressed: () => navigateTo(context, stop),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MeterInputs extends StatelessWidget {
  final bool km;
  final bool hours;
  final TextEditingController kmController;
  final TextEditingController hoursController;
  final String? error;
  final VoidCallback onChanged;

  const _MeterInputs({
    required this.km,
    required this.hours,
    required this.kmController,
    required this.hoursController,
    required this.error,
    required this.onChanged,
  });

  Widget _field(String title, String hint, TextEditingController controller, TextInputType type) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Row(
        children: <Widget>[
          SizedBox(width: 110, child: Text(title, style: TextStyle(fontSize: 16, color: AppColors.text))),
          Expanded(
            child: CupertinoTextField(
              controller: controller,
              keyboardType: type,
              placeholder: hint,
              textAlign: TextAlign.right,
              placeholderStyle: TextStyle(fontSize: 16, color: IosColors.tertiaryLabel),
              style: TextStyle(fontSize: 16, color: error == null ? AppColors.text : IosColors.red),
              padding: const EdgeInsets.fromLTRB(8, 13, 16, 13),
              decoration: null,
              onChanged: (_) => onChanged(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[
      if (km) _field(t('tripDetail.meter.km'), t('tripDetail.meter.kmPlaceholder'), kmController, TextInputType.number),
      if (hours) _field(t('tripDetail.meter.hours'), t('tripDetail.meter.hoursPlaceholder'), hoursController, const TextInputType.numberWithOptions(decimal: true)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 7),
          child: Text(t('tripDetail.meter.header').toUpperCase(),
              style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel, letterSpacing: 0.2)),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ColoredBox(
            color: AppColors.surface,
            child: Column(
              children: <Widget>[
                for (int index = 0; index < rows.length; index++) ...<Widget>[
                  if (index > 0) Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Container(height: 0.5, color: IosColors.separator),
                  ),
                  rows[index],
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
          child: Text(
            error ?? t('common.optional'),
            style: TextStyle(fontSize: 13, color: error == null ? IosColors.secondaryLabel : IosColors.red, height: 1.35),
          ),
        ),
      ],
    );
  }
}

/// Nút viên thuốc nền nhạt cùng màu chữ (kiểu nút "tinted" của iOS)
class _TintButton extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final bool expand;
  final VoidCallback? onPressed;

  const _TintButton({required this.icon, required this.text, required this.color, this.expand = false, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      minimumSize: const Size(44, 42),
      color: color.withValues(alpha: 0.12),
      disabledColor: const Color(0x0F787880),
      borderRadius: BorderRadius.circular(999),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 17, color: onPressed == null ? IosColors.tertiaryLabel : color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: onPressed == null ? IosColors.tertiaryLabel : color),
            ),
          ),
        ],
      ),
    );
  }
}

class _TripInfo extends StatelessWidget {
  final MyTrip trip;

  const _TripInfo({required this.trip});

  Widget _row(String name, String value, {Widget? trailing}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, trailing == null ? 12 : 4, trailing == null ? 16 : 4, trailing == null ? 12 : 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Text(name, style: TextStyle(fontSize: 16, color: AppColors.text)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value, textAlign: TextAlign.right, style: TextStyle(fontSize: 16, color: IosColors.secondaryLabel)),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TripVehicle? mine = trip.myVehicle;
    final List<Widget> rows = <Widget>[
      _row(t('tripDetail.info.role'), tEnum('crewRole', trip.myRole)),
      if (mine != null) _row(t('tripDetail.info.vehicle'), '${mine.displayName} · ${mine.vehicleType}'),
      for (final TripVehicle vehicle in trip.vehicles)
        if (vehicle.publicId != mine?.publicId) _row(t('tripDetail.info.otherVehicle'), '${vehicle.displayName} · ${vehicle.vehicleType}'),
      if (trip.cargoKg != null && trip.cargoKg! > 0) _row(t('tripDetail.info.cargo'), formatKg(trip.cargoKg)),
      _row(t('tripDetail.info.order'), '${trip.orderCode} · ${tEnum('orderStatus', trip.orderStatus)}'),
      if ((trip.note ?? '').isNotEmpty) _row(t('tripDetail.info.note'), trip.note!),
      for (final TripCrew person in trip.crew)
        _row(
          tEnum('crewRole', person.role),
          person.fullName,
          trailing: person.phone.isEmpty
              ? const SizedBox(width: 12)
              : CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  onPressed: () => callPhone(context, person.phone),
                  child: Icon(CupertinoIcons.phone_fill, size: 20, color: IosColors.green, semanticLabel: t('tripDetail.callName', <String, Object?>{'name': person.fullName})),
                ),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 7),
          child: Text(t('tripDetail.info.header').toUpperCase(),
              style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel, letterSpacing: 0.2)),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ColoredBox(
            color: AppColors.surface,
            child: Column(
              children: <Widget>[
                for (int index = 0; index < rows.length; index++) ...<Widget>[
                  if (index > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Container(height: 0.5, color: IosColors.separator),
                    ),
                  rows[index],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Thay nút vuốt khi định vị chưa sẵn sàng: phải bật chia sẻ / GPS / quyền vị trí mới làm chuyến tiếp được
class _LocationRequiredPanel extends ConsumerWidget {
  final LocationGate gate;

  const _LocationRequiredPanel({required this.gate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool checking = gate == LocationGate.checking;
    return Glass(
      borderRadius: BorderRadius.circular(24),
      opacity: 0.9,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              IosIconBadge(
                icon: checking ? CupertinoIcons.location : CupertinoIcons.location_slash_fill,
                color: checking ? const Color(0xFF8E8E93) : IosColors.red,
                size: 32,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  locationGateText(gate),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    color: checking ? AppColors.label : AppColors.errorText,
                  ),
                ),
              ),
            ],
          ),
          if (!checking) ...<Widget>[
            const SizedBox(height: 12),
            IosPillButton(
              label: locationGateAction(gate),
              icon: CupertinoIcons.location_fill,
              onPressed: () async {
                final bool openConsent = await ref.read(locationGateProvider.notifier).fix();
                if (openConsent && context.mounted) {
                  context.push('/driver/location-consent');
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}
