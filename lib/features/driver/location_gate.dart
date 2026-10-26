// Luật công ty: PHẢI chia sẻ vị trí mới làm chuyến được, và đang làm chuyến thì KHÔNG tắt được.
// - "Sẵn sàng" = đã đồng ý chia sẻ + GPS máy đang bật + app có quyền vị trí.
// - Chưa sẵn sàng thì nút vuốt mốc bị thay bằng hướng dẫn bật lại (trip_detail_screen.dart).
// - Đang làm chuyến (đã bấm mốc đầu, chưa xong mọi điểm) thì ẩn nút "Tắt" chia sẻ (location_consent_screen.dart).
// - Tắt GPS / thu hồi quyền trong Cài đặt máy thì app không ngăn được, nhưng phát hiện ngay
//   (theo dõi trạng thái GPS, kiểm lại khi mở lại app) và chặn bấm mốc tới khi bật lại.
//   Điều phối cũng thấy "Mất tín hiệu" sau 15 phút (TRIP_SIGNAL_LOST của backend).
// LƯU Ý: backend hiện vẫn cho bấm mốc không kèm vị trí và cho rút lại đồng ý lúc nào cũng được
// (BR-TRK-001). Muốn chặn chắc chắn (kể cả người dùng web) thì phải đổi luật ở backend.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'driver_api.dart';
import 'driver_providers.dart';

enum LocationGate {
  // Kiểm chưa xong
  checking,
  ready,
  // Chưa đồng ý chia sẻ (hoặc đã rút lại)
  noConsent,
  // GPS của máy đang tắt
  serviceOff,
  // Chưa cấp quyền vị trí (còn hỏi lại được)
  permissionDenied,
  // Đã chặn hẳn quyền: phải vào Cài đặt
  permissionBlocked,
}

/// Câu giải thích cho từng trạng thái chưa sẵn sàng
String locationGateText(LocationGate gate) {
  switch (gate) {
    case LocationGate.noConsent:
      return 'Phải bật chia sẻ vị trí mới làm chuyến được.';
    case LocationGate.serviceOff:
      return 'GPS của máy đang tắt. Bật lại định vị để tiếp tục chuyến.';
    case LocationGate.permissionDenied:
      return 'LiftMate chưa được phép lấy vị trí. Cho phép để tiếp tục chuyến.';
    case LocationGate.permissionBlocked:
      return 'Quyền vị trí của LiftMate đang bị chặn. Vào Cài đặt, cho phép "Vị trí" để tiếp tục.';
    case LocationGate.checking:
      return 'Đang kiểm tra định vị...';
    case LocationGate.ready:
      return '';
  }
}

/// Chữ trên nút sửa cho từng trạng thái
String locationGateAction(LocationGate gate) {
  switch (gate) {
    case LocationGate.noConsent:
      return 'Bật chia sẻ vị trí';
    case LocationGate.serviceOff:
      return 'Bật GPS';
    case LocationGate.permissionDenied:
      return 'Cho phép vị trí';
    case LocationGate.permissionBlocked:
      return 'Mở Cài đặt';
    case LocationGate.checking:
    case LocationGate.ready:
      return '';
  }
}

/// Chuyến đang làm dở: trong khung chuyến, đã bấm ít nhất một mốc, còn việc
MyTrip? tripInProgress(List<MyTrip> trips) {
  for (final MyTrip trip in trips) {
    if (trip.trackingActive && trip.nextAction != null && trip.milestones.isNotEmpty) {
      return trip;
    }
  }
  return null;
}

class LocationGateNotifier extends Notifier<LocationGate> {
  StreamSubscription<ServiceStatus>? _service;
  AppLifecycleListener? _lifecycle;

  @override
  LocationGate build() {
    // Đổi đồng ý thì kiểm lại
    ref.listen<AsyncValue<ConsentState>>(consentProvider, (AsyncValue<ConsentState>? previous, AsyncValue<ConsentState> next) {
      check();
    });
    try {
      _service = Geolocator.getServiceStatusStream().listen((ServiceStatus _) => check());
    } catch (_) {
      // Nền tảng không hỗ trợ theo dõi GPS: vẫn kiểm khi mở lại app
    }
    _lifecycle = AppLifecycleListener(onResume: check);
    ref.onDispose(() {
      _service?.cancel();
      _lifecycle?.dispose();
    });
    Future<void>.microtask(check);
    return LocationGate.checking;
  }

  // Số lượt kiểm: nhiều lượt chạy chồng nhau (đổi đồng ý, bật GPS, mở lại app) thì chỉ lượt mới nhất được ghi,
  // tránh lượt cũ (đọc lúc còn "đã đồng ý") về sau ghi đè thành "đang chia sẻ".
  int _run = 0;

  Future<void> check() async {
    final int run = ++_run;
    final LocationGate result = await _evaluate();
    if (ref.mounted && run == _run) {
      state = result;
    }
  }

  Future<LocationGate> _evaluate() async {
    ConsentState? consent;
    try {
      // Đã có giá trị (vừa bật / tắt) thì dùng ngay giá trị mới nhất, chưa có mới đợi tải
      final AsyncValue<ConsentState> current = ref.read(consentProvider);
      consent = current.hasValue ? current.value : await ref.read(consentProvider.future);
    } catch (_) {
      consent = null;
    }
    if (consent == null || !consent.accepted) {
      return LocationGate.noConsent;
    }
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocationGate.serviceOff;
      }
      final LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.deniedForever) {
        return LocationGate.permissionBlocked;
      }
      if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) {
        return LocationGate.permissionDenied;
      }
    } catch (_) {
      return LocationGate.serviceOff;
    }
    return LocationGate.ready;
  }

  /// Làm theo nút sửa. Trả true khi cần mở màn đồng ý (bên gọi tự điều hướng).
  Future<bool> fix() async {
    switch (state) {
      case LocationGate.noConsent:
        return true;
      case LocationGate.serviceOff:
        await Geolocator.openLocationSettings();
        break;
      case LocationGate.permissionDenied:
        final LocationPermission permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.deniedForever) {
          await Geolocator.openAppSettings();
        }
        break;
      case LocationGate.permissionBlocked:
        await Geolocator.openAppSettings();
        break;
      case LocationGate.checking:
      case LocationGate.ready:
        break;
    }
    await check();
    return false;
  }
}

final locationGateProvider = NotifierProvider<LocationGateNotifier, LocationGate>(LocationGateNotifier.new);
