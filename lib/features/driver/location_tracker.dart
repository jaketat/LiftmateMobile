// T8: gửi vị trí khi đang chạy chuyến (doc slice D mục 5).
// - Chuyến có trackingActive = true và tài xế đã đồng ý thì gửi.
// - Ghi hành trình (chốt 2026-11-04): từ lúc bấm "đã tới" điểm bốc tới khi xong mọi điểm, gửi ĐỦ mọi điểm đo được
//   (cách nhau ~20 m) để điều phối xem đường xe chạy, kể cả khi app chạy nền hay khóa màn hình (iOS hiện thanh xanh,
//   Android hiện thông báo cố định). Trước mốc đó (đang đi tới điểm bốc) chỉ gửi khi app đang mở, mỗi nhịp một điểm như dưới.
// - Giống web (locationSender.ts): máy chỉ nhớ vị trí MỚI NHẤT; tới mỗi nhịp mới đưa điểm đó vào hàng đợi
//   (tối đa 100, đầy thì bỏ điểm cũ nhất) rồi gửi cả hàng đợi. Nhịp do server quyết (nextIntervalSeconds:
//   30 giây khi xe chạy, 300 giây khi đứng yên). Có vị trí đầu tiên thì gửi ngay, không đợi hết nhịp.
// - Nhận 200 thì xóa mọi điểm vừa gửi, kể cả điểm bị rejected. Mất mạng: giữ hàng đợi, gửi lần sau.
// - Kết quả trackingActive = false, 403 LOCATION_CONSENT_REQUIRED, 404 DISPATCH_TRIP_NOT_FOUND: dừng.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/api/call.dart';
import 'driver_api.dart';
import 'driver_providers.dart';
import '../../core/i18n.dart';

const int maxQueuedPoints = 100;
// Lúc ghi hành trình giữ được ~3.000 điểm khi mất sóng (khoảng 60 km), gửi bù mỗi lô 100 điểm (giới hạn của API)
const int maxRecordedPoints = 3000;
const int maxBatchPoints = 100;
const int recordDistanceFilterM = 20;
// Điểm sai số lớn hơn thì không đưa vào đường đi
const double maxRecordAccuracyM = 200;
const int defaultIntervalSeconds = 30;

/// Chuyến đang ở đoạn ghi hành trình: đã bấm "đã tới" một điểm bốc và còn việc phải làm
bool tripRecordsPath(MyTrip trip) {
  if (trip.nextAction == null) return false;
  for (final TripMilestone milestone in trip.milestones) {
    if (milestone.kind == 'Arrived' && trip.stopAt(milestone.stopSequence)?.kind == 'Pickup') return true;
  }
  return false;
}

/// Cấu hình đo vị trí: lúc ghi hành trình thì đo cả khi app chạy nền
LocationSettings trackerLocationSettings({required bool recording}) {
  if (!recording) return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 15);
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: recordDistanceFilterM,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    case TargetPlatform.android:
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: recordDistanceFilterM,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: t('location.recording.notificationTitle'),
          notificationText: t('location.recording.notificationText'),
          notificationChannelName: t('location.recording.channel'),
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    default:
      return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: recordDistanceFilterM);
  }
}

class TrackerState {
  // Chuyến đang gửi vị trí; null: không gửi
  final String? tripId;
  final bool running;
  // Đang ghi hành trình (gửi đủ điểm, chạy nền)
  final bool recording;
  final DateTime? lastSentAt;
  // Số điểm còn giữ chưa gửi được (mất sóng)
  final int pending;
  final Position? lastPosition;
  // Lần gửi gần nhất lỗi mạng: đang giữ điểm, gửi bù khi có sóng
  final bool offline;
  // Câu báo khi không gửi được (chưa cấp quyền, tắt GPS)
  final String? problem;

  const TrackerState({
    this.tripId,
    this.running = false,
    this.recording = false,
    this.lastSentAt,
    this.pending = 0,
    this.lastPosition,
    this.offline = false,
    this.problem,
  });

  TrackerState copyWith({
    String? tripId,
    bool clearTrip = false,
    bool? running,
    bool? recording,
    DateTime? lastSentAt,
    int? pending,
    Position? lastPosition,
    bool? offline,
    String? problem,
    bool clearProblem = false,
  }) {
    return TrackerState(
      tripId: clearTrip ? null : (tripId ?? this.tripId),
      running: running ?? this.running,
      recording: recording ?? this.recording,
      lastSentAt: lastSentAt ?? this.lastSentAt,
      pending: pending ?? this.pending,
      lastPosition: lastPosition ?? this.lastPosition,
      offline: offline ?? this.offline,
      problem: clearProblem ? null : (problem ?? this.problem),
    );
  }
}

class LocationTracker extends Notifier<TrackerState> {
  final List<LocationPoint> _queue = <LocationPoint>[];
  LocationPoint? _latest;
  bool _firstSent = false;
  StreamSubscription<Position>? _positions;
  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  int _intervalSeconds = defaultIntervalSeconds;
  bool _sending = false;
  bool _paused = false;
  // App đang ở nền (khóa màn hình, mở app khác): điểm đo lúc này ghi nguồn Background
  bool _hidden = false;
  // syncTrips được gọi từ nhiều chỗ, có thể chồng nhau: lần gọi sau thắng, lần trước dừng sau mỗi bước chờ.
  // Không chặn thì hai lần cùng mở luồng vị trí, luồng thừa giữ cấu hình cũ (iOS dùng chung một luồng) nên không chạy nền được
  int _startGeneration = 0;

  @override
  TrackerState build() {
    _lifecycle = AppLifecycleListener(
      onHide: _pause,
      onShow: _resume,
    );
    ref.onDispose(() {
      _stopStreams();
      _lifecycle?.dispose();
    });
    return const TrackerState();
  }

  /// Gọi mỗi khi danh sách chuyến tải xong: chọn chuyến đang chạy để gửi vị trí.
  Future<void> syncTrips(List<MyTrip> trips) async {
    MyTrip? active;
    for (final MyTrip trip in trips) {
      if (trip.trackingActive && trip.nextAction != null) {
        active = trip;
        break;
      }
    }
    if (active == null) {
      for (final MyTrip trip in trips) {
        if (trip.trackingActive) {
          active = trip;
          break;
        }
      }
    }
    if (active == null) {
      stop();
      return;
    }
    await start(active.publicId, recording: tripRecordsPath(active));
  }

  Future<void> start(String tripId, {bool recording = false}) async {
    if (state.running && state.tripId == tripId && state.recording == recording) {
      return;
    }
    final int generation = ++_startGeneration;
    // Đổi chuyến thì bỏ hàng đợi của chuyến cũ. Cùng chuyến mà bắt đầu hoặc thôi ghi hành trình thì giữ hàng đợi, chỉ đổi cách đo
    if (state.tripId != tripId) {
      _queue.clear();
      _latest = null;
    }
    _firstSent = false;
    _stopStreams();

    final ConsentState? consent = await _consent();
    if (generation != _startGeneration) return;
    if (consent == null || !consent.accepted) {
      state = state.copyWith(tripId: tripId, running: false, clearProblem: true, pending: _queue.length);
      return;
    }
    final bool serviceOn = await Geolocator.isLocationServiceEnabled();
    if (generation != _startGeneration) return;
    if (!serviceOn) {
      state = state.copyWith(tripId: tripId, running: false, problem: t('location.gate.serviceOff'));
      return;
    }
    final LocationPermission permission = await Geolocator.checkPermission();
    if (generation != _startGeneration) return;
    if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) {
      state = state.copyWith(tripId: tripId, running: false, problem: t('location.gate.permissionDenied'));
      return;
    }

    state = state.copyWith(tripId: tripId, running: true, recording: recording, clearProblem: true, pending: _queue.length);
    if (_paused && !recording) {
      return;
    }
    _listen();
  }

  void stop() {
    _startGeneration++;
    _stopStreams();
    _queue.clear();
    _latest = null;
    state = TrackerState(lastPosition: state.lastPosition);
  }

  void _listen() {
    _positions?.cancel();
    _positions = Geolocator.getPositionStream(
      locationSettings: trackerLocationSettings(recording: state.recording),
    ).listen(_onPosition, onError: (Object _) {
      state = state.copyWith(problem: t('location.problem.noFix'));
    });
    _schedule();
  }

  void _onPosition(Position position) {
    // speed của máy là m/s; âm hoặc 0 khi máy không đo được thì để server tự tính
    final double? speedKmh = position.speed > 0 ? position.speed * 3.6 : null;
    final double? heading = position.heading >= 0 ? position.heading : null;
    final LocationPoint point = LocationPoint(
      recordedAt: position.timestamp,
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyM: position.accuracy.roundToDouble(),
      speedKmh: speedKmh?.roundToDouble(),
      heading: heading?.roundToDouble(),
      source: _hidden ? 'Background' : 'Foreground',
    );
    if (state.recording) {
      // Ghi hành trình: giữ mọi điểm đủ chính xác, đầy thì bỏ điểm cũ nhất
      if (position.accuracy <= maxRecordAccuracyM) {
        _queue.add(point);
        if (_queue.length > maxRecordedPoints) _queue.removeRange(0, _queue.length - maxRecordedPoints);
      }
    } else {
      _latest = point;
    }
    state = state.copyWith(lastPosition: position, clearProblem: true, pending: _queue.length);
    if (!_firstSent) {
      _firstSent = true;
      unawaited(flush());
    }
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(Duration(seconds: _intervalSeconds), () async {
      await flush();
      if (state.running && (!_paused || state.recording)) {
        _schedule();
      }
    });
  }

  /// Gửi cả hàng đợi ngay (gọi theo nhịp, hoặc khi vừa bấm mốc)
  Future<void> flush() async {
    final String? tripId = state.tripId;
    if (tripId == null || _sending) {
      return;
    }
    if (_latest != null) {
      _queue.add(_latest!);
      _latest = null;
      // Vừa thôi ghi hành trình thì hàng đợi còn điểm đường đi chưa gửi: đừng cắt xuống 100 điểm
      final int cap = _queue.length > maxQueuedPoints + 1 ? maxRecordedPoints : maxQueuedPoints;
      while (_queue.length > cap) {
        _queue.removeAt(0);
      }
    }
    if (_queue.isEmpty) {
      return;
    }
    _sending = true;
    try {
      // Gửi lần lượt từng lô 100 điểm, cũ trước; lô nào lỗi thì dừng, giữ phần còn lại cho lần sau
      while (_queue.isNotEmpty && state.tripId == tripId) {
        final List<LocationPoint> batch = _queue.sublist(0, _queue.length < maxBatchPoints ? _queue.length : maxBatchPoints);
        final LocationSendResult result = await sendTripLocations(tripId, batch);
        _queue.removeRange(0, batch.length <= _queue.length ? batch.length : _queue.length);
        _intervalSeconds = result.nextIntervalSeconds >= 5 ? result.nextIntervalSeconds : (result.nextIntervalSeconds > 0 ? 5 : defaultIntervalSeconds);
        state = state.copyWith(lastSentAt: DateTime.now(), pending: _queue.length, offline: false);
        if (!result.trackingActive) {
          stop();
          break;
        }
      }
    } on ApiException catch (error) {
      if (error.status == null) {
        // Mất mạng: giữ hàng đợi, lần sau gửi bù
        state = state.copyWith(pending: _queue.length, offline: true);
      } else if (error.code == 'LOCATION_CONSENT_REQUIRED') {
        stop();
        await ref.read(consentProvider.notifier).reload();
      } else if (error.status == 404) {
        stop();
        ref.invalidate(driverTripsProvider);
      } else if (error.status == 400) {
        // Lô sai cấu trúc: bỏ, đừng gửi lại mãi
        _queue.clear();
        state = state.copyWith(pending: 0);
      }
    } finally {
      _sending = false;
    }
  }

  void _pause() {
    _paused = true;
    _hidden = true;
    // Đang ghi hành trình thì vẫn đo và gửi khi app ở nền
    if (state.recording) return;
    _positions?.cancel();
    _positions = null;
    _timer?.cancel();
    _timer = null;
  }

  void _resume() {
    _paused = false;
    _hidden = false;
    if (state.running && _positions == null) {
      _listen();
      unawaited(flush());
    }
  }

  void _stopStreams() {
    _positions?.cancel();
    _positions = null;
    _timer?.cancel();
    _timer = null;
    _intervalSeconds = defaultIntervalSeconds;
  }

  Future<ConsentState?> _consent() async {
    try {
      return await ref.read(consentProvider.future);
    } catch (_) {
      return null;
    }
  }
}

final locationTrackerProvider = NotifierProvider<LocationTracker, TrackerState>(LocationTracker.new);
