// Bản đồ tĩnh ghép từ ô ảnh của Vietmap, vẽ bằng Flutter: nằm trong trang cuộn và sheet vẫn mượt,
// vì bản đồ native (VietmapGL) không được di chuyển. Xem rộng hơn thì mở màn bản đồ thật.
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:vietmap_flutter_gl/vietmap_flutter_gl.dart' show LatLng;

import '../../core/env.dart';
import '../../core/theme.dart';

const double _tileSize = 256;

/// Một điểm vẽ trên bản đồ
class StaticMapStop {
  final LatLng point;
  final Color color;
  final String label;

  const StaticMapStop({required this.point, required this.color, required this.label});
}

/// Khung nhìn: mức zoom và góc trên trái, tính theo điểm ảnh của cả thế giới ở mức zoom đó
class StaticMapView {
  final int zoom;
  final double left;
  final double top;

  const StaticMapView({required this.zoom, required this.left, required this.top});

  Offset project(LatLng point) => worldPixel(point, zoom) - Offset(left, top);
}

/// Toạ độ sang điểm ảnh Web Mercator
Offset worldPixel(LatLng point, int zoom) {
  final double scale = _tileSize * math.pow(2, zoom);
  final double x = (point.longitude + 180) / 360 * scale;
  final double sinLat = math.sin(point.latitude * math.pi / 180).clamp(-0.9999, 0.9999);
  final double y = (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) * scale;
  return Offset(x, y);
}

/// Mức zoom lớn nhất mà mọi điểm vẫn lọt trong khung trừ lề, đặt ở giữa khung
StaticMapView fitStaticMap(List<LatLng> points, Size size, EdgeInsets padding, {int maxZoom = 15}) {
  final double width = math.max(1, size.width - padding.horizontal);
  final double height = math.max(1, size.height - padding.vertical);
  int zoom = maxZoom;
  late Rect bounds;
  while (true) {
    final List<Offset> pixels = <Offset>[for (final LatLng point in points) worldPixel(point, zoom)];
    double minX = pixels.first.dx, maxX = pixels.first.dx, minY = pixels.first.dy, maxY = pixels.first.dy;
    for (final Offset pixel in pixels) {
      minX = math.min(minX, pixel.dx);
      maxX = math.max(maxX, pixel.dx);
      minY = math.min(minY, pixel.dy);
      maxY = math.max(maxY, pixel.dy);
    }
    bounds = Rect.fromLTRB(minX, minY, maxX, maxY);
    if (zoom <= 3 || (bounds.width <= width && bounds.height <= height)) break;
    zoom--;
  }
  final Offset center = bounds.center + Offset((padding.left - padding.right) / -2, (padding.top - padding.bottom) / -2);
  return StaticMapView(zoom: zoom, left: center.dx - size.width / 2, top: center.dy - size.height / 2);
}

class StaticRouteMap extends StatelessWidget {
  final List<StaticMapStop> stops;
  // Đường xe tải đã tính; null thì nối thẳng các điểm
  final List<LatLng>? route;
  final double height;
  final VoidCallback? onTap;
  final String? semanticLabel;

  const StaticRouteMap({super.key, required this.stops, this.route, required this.height, this.onTap, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    if (stops.isEmpty || Env.vietmapKey.isEmpty) return const SizedBox.shrink();
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Size size = Size(constraints.maxWidth, height);
              final List<LatLng> line = (route?.length ?? 0) >= 2 ? route! : <LatLng>[for (final StaticMapStop stop in stops) stop.point];
              final StaticMapView view = fitStaticMap(<LatLng>[...line, for (final StaticMapStop stop in stops) stop.point], size, const EdgeInsets.all(36));
              return RepaintBoundary(
                child: ClipRect(
                  child: ColoredBox(
                    color: AppColors.hairline,
                    child: Stack(
                      children: <Widget>[
                        ..._tiles(view, size),
                        Positioned.fill(child: CustomPaint(painter: _RoutePainter(view: view, line: line, stops: stops))),
                        Positioned(
                          right: 8,
                          bottom: 4,
                          child: Text(Env.mapAttribution, style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _tiles(StaticMapView view, Size size) {
    final String style = AppColors.isDark ? 'dm' : 'tm';
    final int count = 1 << view.zoom;
    final int fromX = (view.left / _tileSize).floor();
    final int toX = ((view.left + size.width) / _tileSize).floor();
    final int fromY = (view.top / _tileSize).floor();
    final int toY = ((view.top + size.height) / _tileSize).floor();
    return <Widget>[
      for (int y = fromY; y <= toY; y++)
        if (y >= 0 && y < count)
          for (int x = fromX; x <= toX; x++)
            Positioned(
              left: x * _tileSize - view.left,
              top: y * _tileSize - view.top,
              width: _tileSize,
              height: _tileSize,
              child: CachedNetworkImage(
                imageUrl: 'https://maps.vietmap.vn/maps/tiles/$style/${view.zoom}/${x % count}/$y@2x.png?apikey=${Env.vietmapKey}',
                fit: BoxFit.fill,
                fadeInDuration: const Duration(milliseconds: 120),
                errorWidget: (BuildContext context, String url, Object error) => const SizedBox.shrink(),
              ),
            ),
    ];
  }
}

class _RoutePainter extends CustomPainter {
  final StaticMapView view;
  final List<LatLng> line;
  final List<StaticMapStop> stops;

  const _RoutePainter({required this.view, required this.line, required this.stops});

  @override
  void paint(Canvas canvas, Size size) {
    if (line.length >= 2) {
      final Path path = Path();
      for (int index = 0; index < line.length; index++) {
        final Offset point = view.project(line[index]);
        index == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
      }
      Paint stroke(Color color, double width) => Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = color
        ..strokeWidth = width;
      canvas.drawPath(path, stroke(Colors.white, 7));
      canvas.drawPath(path, stroke(const Color(0xFF2E6BE6), 4));
    }
    for (final StaticMapStop stop in stops) {
      final Offset center = view.project(stop.point);
      canvas.drawCircle(
        center.translate(0, 2),
        14,
        Paint()
          ..color = const Color(0x330C2858)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawCircle(center, 14, Paint()..color = Colors.white);
      canvas.drawCircle(center, 11.5, Paint()..color = stop.color);
      final TextPainter label = TextPainter(
        text: TextSpan(text: stop.label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, center - Offset(label.width / 2, label.height / 2));
      label.dispose();
    }
  }

  @override
  bool shouldRepaint(_RoutePainter oldDelegate) {
    return oldDelegate.view.left != view.left || oldDelegate.view.top != view.top || oldDelegate.view.zoom != view.zoom || !identical(oldDelegate.line, line) || !identical(oldDelegate.stops, stops);
  }
}
