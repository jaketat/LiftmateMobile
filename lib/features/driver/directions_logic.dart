// Chỉ đường xe tải: phần tính toán thuần, không gọi mạng, không vẽ, để test được.
// Server trả tuyến một lần; app tự theo dõi vị trí trên tuyến đó, không tốn lượt gọi Vietmap.
// Hướng rẽ tính từ hình dạng tuyến, không dùng "sign" của Vietmap: tài liệu không công bố bảng mã,
// đoán sai mũi tên thì dẫn xe tải đi nhầm đường.
import 'dart:math' as math;

import 'package:vietmap_flutter_gl/vietmap_flutter_gl.dart' show LatLng;

/// Giải mã polyline định dạng Google, độ chính xác 5 (backend: PolylineCodec)
List<LatLng> decodePolyline(String encoded) {
  final List<LatLng> points = <LatLng>[];
  int index = 0;
  int lat = 0;
  int lng = 0;
  int nextValue() {
    int shift = 0;
    int result = 0;
    int byte;
    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    return (result & 1) != 0 ? ~(result >> 1) : result >> 1;
  }

  while (index < encoded.length) {
    lat += nextValue();
    lng += nextValue();
    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return points;
}

double metersBetween(LatLng a, LatLng b) {
  double rad(double degree) => degree * math.pi / 180;
  final double dLat = rad(b.latitude - a.latitude);
  final double dLng = rad(b.longitude - a.longitude);
  final double h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.latitude)) * math.cos(rad(b.latitude)) * math.pow(math.sin(dLng / 2), 2);
  return 6371000 * 2 * math.asin(math.sqrt(h));
}

/// Vị trí xe so với tuyến
class RouteProgress {
  // Đoạn gần nhất: nằm giữa điểm [segment] và [segment] + 1 của tuyến
  final int segment;
  final double offRouteM;
  final double remainingM;

  const RouteProgress({required this.segment, required this.offRouteM, required this.remainingM});
}

/// Tuyến đã giải mã, kèm quãng đường cộng dồn tới từng điểm
class RouteTrack {
  final List<LatLng> points;
  final List<double> cumulativeM;

  RouteTrack(this.points) : cumulativeM = _cumulative(points);

  static List<double> _cumulative(List<LatLng> points) {
    final List<double> result = <double>[];
    double total = 0;
    for (int index = 0; index < points.length; index++) {
      if (index > 0) total += metersBetween(points[index - 1], points[index]);
      result.add(total);
    }
    return result;
  }

  double get totalM => cumulativeM.isEmpty ? 0 : cumulativeM.last;

  RouteProgress progress(LatLng position) {
    if (points.length < 2) {
      return RouteProgress(
        segment: 0,
        offRouteM: points.isEmpty ? double.infinity : metersBetween(position, points.first),
        remainingM: 0,
      );
    }
    int bestSegment = 0;
    double bestDistance = double.infinity;
    double bestAlong = 0;
    // Quãng ngắn nên coi mặt đất là phẳng quanh vị trí xe
    final double metersPerLng = 111320 * math.cos(position.latitude * math.pi / 180);
    const double metersPerLat = 110540;
    for (int index = 0; index < points.length - 1; index++) {
      final double ax = (points[index].longitude - position.longitude) * metersPerLng;
      final double ay = (points[index].latitude - position.latitude) * metersPerLat;
      final double bx = (points[index + 1].longitude - position.longitude) * metersPerLng;
      final double by = (points[index + 1].latitude - position.latitude) * metersPerLat;
      final double dx = bx - ax;
      final double dy = by - ay;
      final double lengthSquared = dx * dx + dy * dy;
      final double ratio = lengthSquared == 0 ? 0 : (-(ax * dx + ay * dy) / lengthSquared).clamp(0.0, 1.0);
      final double px = ax + dx * ratio;
      final double py = ay + dy * ratio;
      final double distance = math.sqrt(px * px + py * py);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestSegment = index;
        bestAlong = cumulativeM[index] + (cumulativeM[index + 1] - cumulativeM[index]) * ratio;
      }
    }
    return RouteProgress(segment: bestSegment, offRouteM: bestDistance, remainingM: math.max(0, totalM - bestAlong));
  }

  /// Hướng rẽ tại điểm [index]: so hướng đi tới với hướng đi tiếp, nhìn xa đủ 15 m để bỏ răng cưa của tuyến
  TurnKind turnAt(int index) {
    if (index <= 0 || index >= points.length - 1) return TurnKind.straight;
    int before = index - 1;
    while (before > 0 && cumulativeM[index] - cumulativeM[before] < 15) {
      before--;
    }
    int after = index + 1;
    while (after < points.length - 1 && cumulativeM[after] - cumulativeM[index] < 15) {
      after++;
    }
    double change = _bearing(points[index], points[after]) - _bearing(points[before], points[index]);
    while (change > 180) {
      change -= 360;
    }
    while (change < -180) {
      change += 360;
    }
    final double size = change.abs();
    if (size < 25) return TurnKind.straight;
    if (size >= 160) return TurnKind.uTurn;
    final bool right = change > 0;
    if (size < 55) return right ? TurnKind.slightRight : TurnKind.slightLeft;
    if (size < 125) return right ? TurnKind.right : TurnKind.left;
    return right ? TurnKind.sharpRight : TurnKind.sharpLeft;
  }

  static double _bearing(LatLng from, LatLng to) {
    double rad(double degree) => degree * math.pi / 180;
    final double dLng = rad(to.longitude - from.longitude);
    final double y = math.sin(dLng) * math.cos(rad(to.latitude));
    final double x = math.cos(rad(from.latitude)) * math.sin(rad(to.latitude)) -
        math.sin(rad(from.latitude)) * math.cos(rad(to.latitude)) * math.cos(dLng);
    return math.atan2(y, x) * 180 / math.pi;
  }
}

enum TurnKind { straight, slightLeft, left, sharpLeft, slightRight, right, sharpRight, uTurn }

/// Việc tiếp theo trên đường: rẽ ở đâu, hoặc [TurnKind] null khi không còn chỗ rẽ nào trước điểm đến
class NextManeuver {
  final TurnKind? turn;
  final String? road;
  final double distanceM;

  const NextManeuver({required this.turn, required this.road, required this.distanceM});
}

/// Bước đầu tiên bắt đầu sau vị trí xe. [stepStarts]: điểm bắt đầu của từng bước (pointIndex), [roads]: tên đường tương ứng.
NextManeuver nextManeuver(RouteTrack track, RouteProgress progress, List<int> stepStarts, List<String?> roads) {
  final int last = track.points.length - 1;
  for (int index = 0; index < stepStarts.length; index++) {
    final int start = stepStarts[index];
    if (start > progress.segment && start < last) {
      final double travelled = track.totalM - progress.remainingM;
      return NextManeuver(
        turn: track.turnAt(start),
        road: roads[index],
        distanceM: math.max(0, track.cumulativeM[start] - travelled),
      );
    }
  }
  return NextManeuver(turn: null, road: null, distanceM: progress.remainingM);
}

/// Khi nào xin tuyến mới: lệch quá 60 m, GPS đủ chính xác, 2 lần đo liên tiếp, cách lần xin trước tối thiểu 30 giây.
/// Mỗi lần xin có thể tốn một lượt Vietmap nên phải chắc xe lệch thật, không phải GPS nhảy.
class RerouteGate {
  static const double offRouteLimitM = 60;
  static const double accuracyLimitM = 30;
  static const Duration minGap = Duration(seconds: 30);

  int _strikes = 0;
  DateTime? _lastRequest;

  /// Gọi khi vừa có tuyến (kể cả xin lỗi): bắt đầu đếm lại khoảng cách tối thiểu
  void markRequested(DateTime now) {
    _lastRequest = now;
    _strikes = 0;
  }

  bool shouldReroute({required double offRouteM, required double accuracyM, required DateTime now}) {
    // GPS kém: không kết luận gì, giữ nguyên số lần đã đếm
    if (accuracyM > accuracyLimitM) return false;
    if (offRouteM <= offRouteLimitM) {
      _strikes = 0;
      return false;
    }
    _strikes++;
    if (_strikes < 2) return false;
    final DateTime? last = _lastRequest;
    return last == null || now.difference(last) >= minGap;
  }
}
