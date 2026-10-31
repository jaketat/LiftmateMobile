// Bản đồ nền của app tài xế, dùng Vietmap giống web (src/features/orders/RouteMapImpl.tsx):
// style 'tm' của Vietmap, khóa TILEMAP truyền bằng --dart-define=VIETMAP_KEY=... (web: VITE_VIETMAP_KEY).
// Khóa TILEMAP chỉ vẽ được bản đồ, lộ trong app cũng không gọi được API tính tiền.
// Vẽ: các điểm của chuyến (đánh số; bốc xanh đậm, trả cam, đi qua xám), đường nối các điểm theo thứ tự,
// chấm xanh vị trí của tôi; tự canh khung cho vừa mọi điểm.
// Đường nối là tuyến xe tải đã lưu của đơn (BR-TRK-011); không có tuyến thì nối thẳng các điểm.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vietmap_flutter_gl/vietmap_flutter_gl.dart';

import '../../core/env.dart';
import '../../core/theme.dart';
import '../../core/widgets/glass.dart';
import 'driver_api.dart';
import '../../core/i18n.dart';

// ------------------------------------------------ Bản đồ thường / vệ tinh
// Vietmap có kiểu "hm" (hybrid): ảnh vệ tinh kèm tên đường, nhãn địa điểm. Cùng khóa TILEMAP với kiểu "tm".
// Lựa chọn được nhớ trên máy, lần sau mở app vẫn giữ.

const String _satelliteKey = 'mapSatellite';

class MapSatelliteNotifier extends Notifier<bool> {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    try {
      if (await _storage.read(key: _satelliteKey) == '1' && ref.mounted) state = true;
    } catch (_) {}
  }

  void toggle() {
    state = !state;
    _storage.write(key: _satelliteKey, value: state ? '1' : '0').catchError((Object _) {});
  }
}

final mapSatelliteProvider = NotifierProvider<MapSatelliteNotifier, bool>(MapSatelliteNotifier.new);

/// Địa chỉ kiểu bản đồ: "tm" (đường phố) hoặc "hm" (vệ tinh có nhãn)
String mapStyleUrl(bool satellite) {
  final String base = Env.vietmapStyle;
  return satellite ? base.replaceFirst('/styles/tm/', '/styles/hm/') : base;
}

/// Nút tròn kính đổi bản đồ thường / vệ tinh
class MapStyleButton extends ConsumerWidget {
  final double size;

  const MapStyleButton({super.key, this.size = 48});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool satellite = ref.watch(mapSatelliteProvider);
    return GlassCircleButton(
      icon: satellite ? CupertinoIcons.map : CupertinoIcons.globe,
      tooltip: satellite ? t('map.standard') : t('map.satellite'),
      size: size,
      onPressed: () => ref.read(mapSatelliteProvider.notifier).toggle(),
    );
  }
}

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

class TripMap extends ConsumerStatefulWidget {
  final List<TripStop> stops;
  final LatLng? me;
  // Chừa chỗ cho thanh trên và sheet dưới khi canh khung các điểm
  final EdgeInsets fitPadding;
  // Điểm đang làm việc tiếp theo: vẽ to hơn
  final int? focusSequence;
  // Trả controller để màn ngoài điều khiển camera (nút "Về vị trí của tôi")
  final ValueChanged<VietmapController>? onMapCreated;
  // Tuyến xe tải đã lưu của đơn; null thì nối thẳng các điểm
  final List<LatLng>? route;
  // Đang chỉ đường: camera bám theo xe, không canh khung cả tuyến
  final bool follow;

  const TripMap({
    super.key,
    required this.stops,
    this.route,
    this.follow = false,
    this.me,
    this.fitPadding = const EdgeInsets.fromLTRB(48, 140, 48, 380),
    this.focusSequence,
    this.onMapCreated,
  });

  @override
  ConsumerState<TripMap> createState() => _TripMapState();
}

/// Đưa một điểm vào giữa vùng bản đồ còn thấy được (trừ phần thanh trên và sheet che), không bị nút nổi đè lên
CameraUpdate focusCamera(LatLng point, EdgeInsets padding, {double span = 0.004}) {
  return CameraUpdate.newLatLngBounds(
    LatLngBounds(
      southwest: LatLng(point.latitude - span, point.longitude - span),
      northeast: LatLng(point.latitude + span, point.longitude + span),
    ),
    left: padding.left,
    top: padding.top,
    right: padding.right,
    bottom: padding.bottom,
  );
}

// Ảnh điểm vẽ gấp 3 rồi thu lại để không nhòe trên màn dày điểm ảnh
const double _imageScale = 3;
const double _shadowPad = 8;

/// Vẽ ảnh một điểm của chuyến: vòng màu viền trắng, số thứ tự ở giữa, bóng mềm
Future<Uint8List> _stopImage(Color color, int number, double size, double fontSize) {
  return _renderImage(size + _shadowPad * 2, (Canvas canvas, Offset center) {
    canvas.drawCircle(
      center.translate(0, 3),
      size / 2,
      Paint()
        ..color = const Color(0x330C2858)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(center, size / 2, Paint()..color = Colors.white);
    canvas.drawCircle(center, size / 2 - 3, Paint()..color = color);
    final TextPainter label = TextPainter(
      text: TextSpan(
        text: '$number',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, center - Offset(label.width / 2, label.height / 2));
    label.dispose();
  });
}

/// Vẽ ảnh chấm xanh vị trí của tôi
Future<Uint8List> _meImage() {
  return _renderImage(56, (Canvas canvas, Offset center) {
    canvas.drawCircle(center, 28, Paint()..color = const Color(0x262E6BE6));
    canvas.drawCircle(center, 10, Paint()..color = Colors.white);
    canvas.drawCircle(center, 6.5, Paint()..color = const Color(0xFF2E6BE6));
  });
}

Future<Uint8List> _renderImage(double size, void Function(Canvas canvas, Offset center) draw) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder)..scale(_imageScale);
  draw(canvas, Offset(size / 2, size / 2));
  final ui.Picture picture = recorder.endRecording();
  final int pixels = (size * _imageScale).ceil();
  final ui.Image image = await picture.toImage(pixels, pixels);
  picture.dispose();
  final ByteData? bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

class _TripMapState extends ConsumerState<TripMap> {
  VietmapController? controller;
  bool styleLoaded = false;
  // Bộ điểm đã vẽ đường và canh khung: chỉ canh lại khi bộ điểm đổi, vị trí của tôi nhích không làm nhảy bản đồ
  String? fittedFor;
  // Bộ điểm (gồm điểm đang làm) đã vẽ dấu lên bản đồ
  String? stopsDrawnFor;
  List<Symbol> stopSymbols = <Symbol>[];
  Symbol? meSymbol;
  LatLng? followedAt;
  // Ảnh đã nạp vào kiểu bản đồ hiện tại
  final Set<String> images = <String>{};
  bool? lastSatellite;
  // Chỉ một lượt vẽ chạy tại một lúc; có thay đổi giữa chừng thì chạy thêm một lượt
  bool syncing = false;
  bool syncAgain = false;
  // Tăng khi bản đồ bị thay / hủy: lượt vẽ đang dở của bản đồ cũ tự bỏ
  int mapEpoch = 0;

  void resetMap() {
    mapEpoch++;
    syncing = false;
    syncAgain = false;
    styleLoaded = false;
    fittedFor = null;
    stopsDrawnFor = null;
    stopSymbols = <Symbol>[];
    meSymbol = null;
    followedAt = null;
    images.clear();
  }

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
    // Thôi bám theo xe, hoặc phần bị che đổi (thẻ chỉ đường hiện ra, sheet thu xuống): canh lại khung cả tuyến
    if ((oldWidget.follow && !widget.follow) || (!widget.follow && oldWidget.fitPadding != widget.fitPadding)) {
      fittedFor = null;
      followedAt = null;
    }
    if (styleLoaded &&
        (routeKey != fittedFor ||
            stopMarkersKey != stopsDrawnFor ||
            widget.me != meSymbol?.options.geometry ||
            (widget.follow && widget.me != followedAt))) {
      syncMap();
    }
  }

  // Khóa đường đang vẽ: đổi bộ điểm hoặc có tuyến mới thì vẽ lại
  String get routeKey {
    final List<LatLng>? route = widget.route;
    if (route == null || route.isEmpty) return stopsKey;
    return '$stopsKey#${route.length}|${route.first.latitude},${route.first.longitude}|${route.last.latitude},${route.last.longitude}';
  }

  @override
  void dispose() {
    mapEpoch++;
    super.dispose();
  }

  // Khóa dấu các điểm: đổi điểm đang làm thì vẽ lại, vị trí của tôi nhích thì không
  String get stopMarkersKey => '$stopsKey#${widget.focusSequence}';

  Future<void> syncMap() async {
    if (syncing) {
      syncAgain = true;
      return;
    }
    syncing = true;
    final int epoch = mapEpoch;
    try {
      do {
        syncAgain = false;
        final VietmapController? map = controller;
        if (map == null || !styleLoaded) return;
        await drawRoute(map, epoch);
        if (epoch != mapEpoch) return;
        await drawStops(map, epoch);
        if (epoch != mapEpoch) return;
        await drawMe(map, epoch);
        if (epoch != mapEpoch) return;
        await followMe(map);
      } while (syncAgain && epoch == mapEpoch);
    } catch (_) {
      // Bản đồ vừa bị hủy (đổi kiểu, rời màn): bản đồ mới sẽ vẽ lại từ đầu
    } finally {
      if (epoch == mapEpoch) syncing = false;
    }
  }

  Future<void> followMe(VietmapController map) async {
    final LatLng? me = widget.me;
    if (!widget.follow || me == null || me == followedAt) return;
    followedAt = me;
    await map.animateCamera(focusCamera(me, widget.fitPadding, span: 0.0015));
  }

  Future<void> drawRoute(VietmapController map, int epoch) async {
    final String key = routeKey;
    if (key == fittedFor) return;
    final List<LatLng> points = (widget.route?.isNotEmpty ?? false) ? widget.route! : stopPoints;
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
    if (epoch != mapEpoch) return;
    fittedFor = key;
    if (!widget.follow) await fitCamera(map);
  }

  Future<void> addImageOnce(VietmapController map, int epoch, String name, Future<Uint8List> Function() render) async {
    if (images.contains(name)) return;
    await map.addImage(name, await render());
    if (epoch == mapEpoch) images.add(name);
  }

  // Dấu do chính bản đồ vẽ nên dính chặt vào bản đồ khi kéo, không phải báo vị trí qua lại với Flutter
  Future<void> drawStops(VietmapController map, int epoch) async {
    final String key = stopMarkersKey;
    if (key == stopsDrawnFor) return;
    final List<SymbolOptions> options = <SymbolOptions>[];
    for (final TripStop stop in widget.stops) {
      if (!stop.hasCoordinates) {
        continue;
      }
      final bool focused = stop.sequence == widget.focusSequence;
      final String name = 'stop_${stop.kind}_${stop.sequence}_$focused';
      await addImageOnce(
        map,
        epoch,
        name,
        () => _stopImage(stopColor(stop.kind), stop.sequence, focused ? 38 : 30, focused ? 14 : 12),
      );
      options.add(SymbolOptions(
        geometry: LatLng(stop.latitude!, stop.longitude!),
        iconImage: name,
        iconSize: 1 / _imageScale,
        iconAnchor: 'center',
        zIndex: focused ? 2 : 1,
      ));
    }
    if (stopSymbols.isNotEmpty) await map.removeSymbols(stopSymbols);
    final List<Symbol> added = options.isEmpty ? <Symbol>[] : await map.addSymbols(options);
    if (epoch != mapEpoch) return;
    stopSymbols = added;
    stopsDrawnFor = key;
  }

  Future<void> drawMe(VietmapController map, int epoch) async {
    final LatLng? me = widget.me;
    final Symbol? current = meSymbol;
    if (me == current?.options.geometry) return;
    if (me == null) {
      await map.removeSymbol(current!);
      if (epoch == mapEpoch) meSymbol = null;
      return;
    }
    if (current != null) {
      await map.updateSymbol(current, SymbolOptions(geometry: me));
      return;
    }
    await addImageOnce(map, epoch, 'me', _meImage);
    final Symbol added = await map.addSymbol(SymbolOptions(
      geometry: me,
      iconImage: 'me',
      iconSize: 1 / _imageScale,
      iconAnchor: 'center',
      zIndex: 3,
    ));
    if (epoch != mapEpoch) return;
    meSymbol = added;
    // Không có điểm nào để canh khung: vị trí vừa có thì đưa bản đồ về đó (lúc tạo bản đồ có thể chưa có vị trí)
    if (stopPoints.isEmpty) await fitCamera(map);
  }

  Future<void> fitCamera(VietmapController map) async {
    // Có tuyến thì canh theo tuyến; vị trí của tôi ở xa không được làm bản đồ thu nhỏ theo
    final bool hasRoute = widget.route?.isNotEmpty ?? false;
    final List<LatLng> all = <LatLng>[...stopPoints, if (hasRoute) ...widget.route!, if (!hasRoute && widget.me != null) widget.me!];
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
      await map.moveCamera(focusCamera(LatLng(south, west), widget.fitPadding));
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

  @override
  Widget build(BuildContext context) {
    if (Env.vietmapKey.isEmpty) {
      // Chưa có khóa: không vẽ bản đồ (giống web), app vẫn dùng được bằng danh sách điểm
      return Container(
        color: const Color(0xFFE9ECF1),
        alignment: const Alignment(0, -0.35),
        padding: const EdgeInsets.all(32),
        // Thiếu khóa VIETMAP_KEY (xem dart_defines.json): chỉ báo bản đồ chưa dùng được
        child: Text(
          t('map.unavailable'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.5),
        ),
      );
    }

    final List<LatLng> points = stopPoints;
    final LatLng start = points.isNotEmpty ? points.first : (widget.me ?? defaultMapCenter);
    final bool satellite = ref.watch(mapSatelliteProvider);
    // Vừa đổi kiểu: bản đồ cũ bị dựng lại, bỏ controller cũ để lớp điểm không bám vào bản đồ đã hủy
    if (lastSatellite != null && lastSatellite != satellite) {
      controller = null;
      resetMap();
    }
    lastSatellite = satellite;

    return VietmapGL(
      // Đổi kiểu bản đồ thì dựng lại bản đồ (vẽ lại đường, canh lại khung trong onStyleLoaded)
      key: ValueKey<bool>(satellite),
      styleString: '${mapStyleUrl(satellite)}?apikey=${Env.vietmapKey}',
      initialCameraPosition: CameraPosition(target: start, zoom: points.isEmpty && widget.me == null ? 9 : 13),
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      compassEnabled: false,
      annotationOrder: const <AnnotationType>[AnnotationType.line, AnnotationType.symbol],
      onMapCreated: (VietmapController created) {
        resetMap();
        controller = created;
        widget.onMapCreated?.call(created);
      },
      onStyleLoadedCallback: () async {
        final int epoch = mapEpoch;
        try {
          // Dấu chuyến luôn hiện, không bị ẩn khi nằm gần nhau hay gần nhãn bản đồ
          await controller?.symbolManager?.setIconAllowOverlap(true);
          await controller?.symbolManager?.setIconIgnorePlacement(true);
        } catch (_) {
          return;
        }
        if (epoch != mapEpoch || !mounted) return;
        styleLoaded = true;
        syncMap();
      },
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
