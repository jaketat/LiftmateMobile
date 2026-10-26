// Bản đồ nền của app tài xế, dùng Vietmap giống web (src/features/orders/RouteMapImpl.tsx):
// style 'tm' của Vietmap, khóa TILEMAP truyền bằng --dart-define=VIETMAP_KEY=... (web: VITE_VIETMAP_KEY).
// Khóa TILEMAP chỉ vẽ được bản đồ, lộ trong app cũng không gọi được API tính tiền.
// Vẽ: các điểm của chuyến (đánh số; bốc xanh đậm, trả cam, đi qua xám), đường nối các điểm theo thứ tự,
// chấm xanh vị trí của tôi; tự canh khung cho vừa mọi điểm.
// Đường nối là đường thẳng giữa các điểm (server không trả lộ trình cho tài xế);
// chỉ đường thật thì bấm "Dẫn đường" mở Google Maps.
import 'package:flutter/material.dart';
import 'package:vietmap_flutter_gl/vietmap_flutter_gl.dart';

import '../../core/env.dart';
import '../../core/theme.dart';
import 'driver_api.dart';

// Trung tâm TP.HCM: dùng khi chưa có điểm nào có tọa độ (web dùng [106.7, 10.8])
final LatLng defaultMapCenter = LatLng(10.8, 106.7);

Color stopColor(String kind) {
  switch (kind) {
    case 'Pickup':
      return AppColors.navy;
    case 'Delivery':
      return AppColors.orange;
    default:
      return AppColors.textMuted;
  }
}

class TripMap extends StatefulWidget {
  final List<TripStop> stops;
  final LatLng? me;
  // Chừa chỗ cho thanh trên và sheet dưới khi canh khung các điểm
  final EdgeInsets fitPadding;
  // Điểm đang làm việc tiếp theo: vẽ to hơn
  final int? focusSequence;
  // Trả controller để màn ngoài điều khiển camera (nút "Về vị trí của tôi")
  final ValueChanged<VietmapController>? onMapCreated;

  const TripMap({
    super.key,
    required this.stops,
    this.me,
    this.fitPadding = const EdgeInsets.fromLTRB(48, 140, 48, 380),
    this.focusSequence,
    this.onMapCreated,
  });

  @override
  State<TripMap> createState() => _TripMapState();
}

class _TripMapState extends State<TripMap> {
  VietmapController? controller;
  bool styleLoaded = false;
  // Bộ điểm đã canh khung lần trước: chỉ canh lại khi bộ điểm đổi, vị trí của tôi nhích không làm nhảy bản đồ
  String fittedFor = '';

  List<LatLng> get stopPoints {
    final List<LatLng> points = <LatLng>[];
    for (final TripStop stop in widget.stops) {
      if (stop.hasCoordinates) {
        points.add(LatLng(stop.latitude!, stop.longitude!));
      }
    }
    return points;
  }

  String get stopsKey => stopPoints.map((LatLng p) => '${p.latitude},${p.longitude}').join('|');

  @override
  void didUpdateWidget(covariant TripMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (styleLoaded && stopsKey != fittedFor) {
      drawRoute();
    }
  }

  Future<void> drawRoute() async {
    final VietmapController? map = controller;
    if (map == null || !styleLoaded) {
      return;
    }
    final List<LatLng> points = stopPoints;
    await map.clearPolylines();
    if (points.length >= 2) {
      await map.addPolyline(PolylineOptions(
        geometry: points,
        polylineColor: AppColors.navy,
        polylineWidth: 5,
        polylineOpacity: 0.85,
        polylineJoin: 'round',
      ));
    }
    fittedFor = stopsKey;
    await fitCamera();
  }

  Future<void> fitCamera() async {
    final VietmapController? map = controller;
    if (map == null) return;
    final List<LatLng> all = <LatLng>[...stopPoints, if (widget.me != null) widget.me!];
    if (all.isEmpty) {
      return;
    }
    double south = all.first.latitude;
    double north = all.first.latitude;
    double west = all.first.longitude;
    double east = all.first.longitude;
    for (final LatLng p in all) {
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
    }
    // Một điểm (hoặc mọi điểm trùng nhau): phóng tới điểm đó
    if ((north - south).abs() < 0.0005 && (east - west).abs() < 0.0005) {
      await map.moveCamera(CameraUpdate.newLatLngZoom(LatLng(south, west), 15));
      return;
    }
    final EdgeInsets pad = widget.fitPadding;
    await map.moveCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(southwest: LatLng(south, west), northeast: LatLng(north, east)),
      left: pad.left,
      top: pad.top,
      right: pad.right,
      bottom: pad.bottom,
    ));
  }

  List<Marker> buildMarkers() {
    final List<Marker> markers = <Marker>[];
    for (final TripStop stop in widget.stops) {
      if (!stop.hasCoordinates) {
        continue;
      }
      final bool focused = stop.sequence == widget.focusSequence;
      final double size = focused ? 38 : 30;
      markers.add(Marker(
        latLng: LatLng(stop.latitude!, stop.longitude!),
        width: size,
        height: size,
        child: Semantics(
          label: 'Điểm ${stop.sequence}: ${stop.address}',
          child: Container(
            decoration: BoxDecoration(
              color: stopColor(stop.kind),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x330C2858), blurRadius: 8, offset: Offset(0, 3))],
            ),
            alignment: Alignment.center,
            child: Text(
              '${stop.sequence}',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: focused ? 14 : 12),
            ),
          ),
        ),
      ));
    }
    final LatLng? me = widget.me;
    if (me != null) {
      markers.add(Marker(
        latLng: me,
        width: 56,
        height: 56,
        child: Semantics(
          label: 'Vị trí của tôi',
          child: Container(
            decoration: const BoxDecoration(color: Color(0x262E6BE6), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: const Color(0xFF2E6BE6),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3.5),
              ),
            ),
          ),
        ),
      ));
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    if (Env.vietmapKey.isEmpty) {
      // Chưa có khóa: không vẽ bản đồ (giống web), app vẫn dùng được bằng danh sách điểm
      return Container(
        color: const Color(0xFFE9ECF1),
        alignment: const Alignment(0, -0.35),
        padding: const EdgeInsets.all(32),
        child: const Text(
          'Chưa có khóa bản đồ Vietmap.\nChạy app với --dart-define=VIETMAP_KEY=<khóa TILEMAP>.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.5),
        ),
      );
    }

    final List<LatLng> points = stopPoints;
    final LatLng start = points.isNotEmpty ? points.first : (widget.me ?? defaultMapCenter);

    return Stack(
      children: <Widget>[
        VietmapGL(
          styleString: '${Env.vietmapStyle}?apikey=${Env.vietmapKey}',
          initialCameraPosition: CameraPosition(target: start, zoom: points.isEmpty && widget.me == null ? 9 : 13),
          // Bắt buộc để MarkerLayer bám theo bản đồ khi kéo, phóng
          trackCameraPosition: true,
          rotateGesturesEnabled: false,
          tiltGesturesEnabled: false,
          compassEnabled: false,
          onMapCreated: (VietmapController created) {
            setState(() {
              controller = created;
            });
            widget.onMapCreated?.call(created);
          },
          onStyleLoadedCallback: () {
            styleLoaded = true;
            drawRoute();
          },
        ),
        if (controller != null)
          MarkerLayer(
            mapController: controller!,
            markers: buildMarkers(),
            ignorePointer: true,
          ),
      ],
    );
  }
}

/// Dòng ghi nguồn bản đồ, đặt ở chân sheet
class MapAttribution extends StatelessWidget {
  const MapAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        Env.mapAttribution,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
      ),
    );
  }
}
