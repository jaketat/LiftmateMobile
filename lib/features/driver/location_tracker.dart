// T8: gửi vị trí khi đang chạy chuyến (doc slice D mục 5).
// - Chỉ gửi khi app đang mở (nền trước), chuyến có trackingActive = true và tài xế đã đồng ý.
// - Giống web (locationSender.ts): máy chỉ nhớ vị trí MỚI NHẤT; tới mỗi nhịp mới đưa điểm đó vào hàng đợi
//   (tối đa 100, đầy thì bỏ điểm cũ nhất) rồi gửi cả hàng đợi. Nhịp do server quyết (nextIntervalSeconds:
//   30 giây khi xe chạy, 300 giây khi đứng yên). Có vị trí đầu tiên thì gửi ngay, không đợi hết nhịp.
// - Nhận 200 thì xóa mọi điểm vừa gửi, kể cả điểm bị rejected. Mất mạng: giữ hàng đợi, gửi lần sau.
// - Kết quả trackingActive = false, 403 LOCATION_CONSENT_REQUIRED, 404 DISPATCH_TRIP_NOT_FOUND: dừng.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/api/call.dart';
import 'driver_api.dart';
import 'driver_providers.dart';

const int maxQueuedPoints = 100;
const int defaultIntervalSeconds = 30;

class TrackerState {
  // Chuyến đang gửi vị trí; null: không gửi
  final String? tripId;
  final bool running;
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
    await start(active.publicId);
  }

  Future<void> start(String tripId) async {
    if (state.running && state.tripId == tripId) {
      return;
    }
    // Đổi chuyến thì bỏ hàng đợi của chuyến cũ (server chỉ giữ điểm mới nhất)
    if (state.tripId != tripId) {
      _queue.clear();
      _latest = null;
    }
    _firstSent = false;
    _stopStreams();

    final ConsentState? consent = await _consent();
    if (consent == null || !consent.accepted) {
      state = state.copyWith(tripId: tripId, running: false, clearProblem: true, pending: _queue.length);
      return;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      state = state.copyWith(tripId: tripId, running: false, problem: 'GPS trên máy đang tắt.');
      return;
    }
    final LocationPermission permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) {
      state = state.copyWith(tripId: tripId, running: false, problem: 'Chưa cấp quyền vị trí cho app.');
      return;
    }

    state = state.copyWith(tripId: tripId, running: true, clearProblem: true, pending: _queue.length);
    if (_paused) {
      return;
    }
    _listen();
  }

  void stop() {
    _stopStreams();
    _queue.clear();
    _latest = null;
    state = TrackerState(lastPosition: state.lastPosition);
  }

  void _listen() {
    _positions = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 15),
    ).listen(_onPosition, onError: (Object _) {
      state = state.copyWith(problem: 'Không lấy được vị trí.');
    });
    _schedule();
  }

  void _onPosition(Position position) {
    // speed của máy là m/s; âm hoặc 0 khi máy không đo được thì để server tự tính
    final double? speedKmh = position.speed > 0 ? position.speed * 3.6 : null;
    final double? heading = position.heading >= 0 ? position.heading : null;
    _latest = LocationPoint(
      recordedAt: position.timestamp,
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyM: position.accuracy.roundToDouble(),
      speedKmh: speedKmh?.roundToDouble(),
      heading: heading?.roundToDouble(),
    );
    state = state.copyWith(lastPosition: position, clearProblem: true);
    if (!_firstSent) {
      _firstSent = true;
      unawaited(flush());
    }
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(Duration(seconds: _intervalSeconds), () async {
      await flush();
      if (state.running && !_paused) {
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
      while (_queue.length > maxQueuedPoints) {
        _queue.removeAt(0);
      }
    }
    if (_queue.isEmpty) {
      return;
    }
    _sending = true;
    final List<LocationPoint> batch = List<LocationPoint>.of(_queue);
    try {
      final LocationSendResult result = await sendTripLocations(tripId, batch);
      _queue.removeRange(0, batch.length <= _queue.length ? batch.length : _queue.length);
      _intervalSeconds = result.nextIntervalSeconds >= 5 ? result.nextIntervalSeconds : (result.nextIntervalSeconds > 0 ? 5 : defaultIntervalSeconds);
      state = state.copyWith(lastSentAt: DateTime.now(), pending: _queue.length, offline: false);
      if (!result.trackingActive) {
        stop();
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
    _positions?.cancel();
    _positions = null;
    _timer?.cancel();
    _timer = null;
  }

  void _resume() {
    _paused = false;
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
