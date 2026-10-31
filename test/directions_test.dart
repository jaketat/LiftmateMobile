// Test chỉ đường xe tải: giải mã tuyến, vị trí trên tuyến, hướng rẽ, khi nào xin tuyến mới (BR-TRK-010).
import 'package:flutter_test/flutter_test.dart';
import 'package:liftmate_mobile/features/driver/directions_logic.dart';
import 'package:liftmate_mobile/features/driver/driver_api.dart';
import 'package:vietmap_flutter_gl/vietmap_flutter_gl.dart' show LatLng;

// Đi lên bắc 1 km, rồi một nhánh tùy hướng 1 km. 0,009 độ vĩ khoảng 1 km.
RouteTrack turning(double dLat, double dLng) {
  return RouteTrack(<LatLng>[
    LatLng(21.0, 105.8),
    LatLng(21.009, 105.8),
    LatLng(21.009 + dLat, 105.8 + dLng),
  ]);
}

void main() {
  test('giải mã polyline theo ví dụ chuẩn của Google', () {
    final List<LatLng> points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    expect(points.length, 3);
    expect(points[0].latitude, closeTo(38.5, 0.00001));
    expect(points[0].longitude, closeTo(-120.2, 0.00001));
    expect(points[2].latitude, closeTo(43.252, 0.00001));
    expect(points[2].longitude, closeTo(-126.453, 0.00001));
    expect(decodePolyline(''), isEmpty);
  });

  test('đọc tuyến server trả: số dạng chuỗi, đường không tên', () {
    final TripDirections parsed = TripDirections.fromJson(<String, dynamic>{
      'stopSequence': 2,
      'distanceKm': '104.32',
      'durationMinutes': 138.5,
      'polyline': 'abc',
      'steps': <dynamic>[
        <String, dynamic>{'sign': 2, 'text': 'Rẽ phải', 'streetName': 'Quốc Lộ 46', 'distanceM': 10, 'durationSeconds': 1, 'pointIndex': 49},
        <String, dynamic>{'sign': 0, 'text': 'Đường X', 'streetName': '', 'distanceM': 10, 'durationSeconds': 1, 'pointIndex': 60},
        <String, dynamic>{'sign': 0, 'text': '', 'streetName': null, 'distanceM': 10, 'durationSeconds': 1, 'pointIndex': 70},
      ],
    });
    expect(parsed.distanceKm, 104.32);
    expect(parsed.steps[0].road, 'Quốc Lộ 46');
    expect(parsed.steps[0].pointIndex, 49);
    expect(parsed.steps[1].road, 'Đường X');
    expect(parsed.steps[2].road, isNull);
  });

  group('hướng rẽ tính từ hình dạng tuyến', () {
    test('rẽ vuông góc phải, trái, đi thẳng, quay đầu', () {
      expect(turning(0, 0.01).turnAt(1), TurnKind.right);
      expect(turning(0, -0.01).turnAt(1), TurnKind.left);
      expect(turning(0.009, 0).turnAt(1), TurnKind.straight);
      expect(turning(-0.009, 0).turnAt(1), TurnKind.uTurn);
    });

    test('chếch và rẽ gắt', () {
      expect(turning(0.009, 0.005).turnAt(1), TurnKind.slightRight);
      expect(turning(0.009, -0.005).turnAt(1), TurnKind.slightLeft);
      expect(turning(-0.009, 0.005).turnAt(1), TurnKind.sharpRight);
      expect(turning(-0.009, -0.005).turnAt(1), TurnKind.sharpLeft);
    });

    test('điểm đầu, điểm cuối không có hướng rẽ', () {
      expect(turning(0, 0.01).turnAt(0), TurnKind.straight);
      expect(turning(0, 0.01).turnAt(2), TurnKind.straight);
    });

    test('răng cưa rất ngắn trên đường thẳng không thành chỗ rẽ', () {
      final RouteTrack track = RouteTrack(<LatLng>[
        LatLng(21.0, 105.8),
        LatLng(21.001, 105.8),
        LatLng(21.00101, 105.80001),
        LatLng(21.002, 105.8),
        LatLng(21.003, 105.8),
      ]);
      expect(track.turnAt(2), TurnKind.straight);
    });
  });

  group('vị trí trên tuyến', () {
    final RouteTrack track = turning(0, 0.01);

    test('xe trên tuyến: không lệch, còn lại đúng phần chưa đi', () {
      final RouteProgress start = track.progress(LatLng(21.0, 105.8));
      expect(start.segment, 0);
      expect(start.offRouteM, lessThan(1));
      expect(start.remainingM, closeTo(track.totalM, 1));

      final RouteProgress secondLeg = track.progress(LatLng(21.009, 105.805));
      expect(secondLeg.segment, 1);
      expect(secondLeg.remainingM, closeTo(track.totalM - track.cumulativeM[1] - metersBetween(LatLng(21.009, 105.8), LatLng(21.009, 105.805)), 5));
    });

    test('xe lệch sang ngang: đo đúng khoảng lệch', () {
      final RouteProgress off = track.progress(LatLng(21.004, 105.801));
      expect(off.offRouteM, closeTo(104, 5));
    });

    test('việc tiếp theo là chỗ rẽ phía trước, qua rồi thì tới điểm đến', () {
      final RouteProgress before = track.progress(LatLng(21.004, 105.8));
      final NextManeuver next = nextManeuver(track, before, <int>[0, 1, 2], <String?>['A', 'B', null]);
      expect(next.turn, TurnKind.right);
      expect(next.road, 'B');
      expect(next.distanceM, closeTo(track.cumulativeM[1] - metersBetween(LatLng(21.0, 105.8), LatLng(21.004, 105.8)), 5));

      final RouteProgress after = track.progress(LatLng(21.009, 105.805));
      final NextManeuver arrive = nextManeuver(track, after, <int>[0, 1, 2], <String?>['A', 'B', null]);
      expect(arrive.turn, isNull);
      expect(arrive.distanceM, closeTo(after.remainingM, 0.1));
    });
  });

  group('khi nào xin tuyến mới', () {
    final DateTime start = DateTime(2026, 10, 31, 8);

    test('phải lệch 2 lần liên tiếp mới xin, GPS nhảy một lần thì không', () {
      final RerouteGate gate = RerouteGate();
      expect(gate.shouldReroute(offRouteM: 100, accuracyM: 10, now: start), isFalse);
      expect(gate.shouldReroute(offRouteM: 10, accuracyM: 10, now: start), isFalse);
      expect(gate.shouldReroute(offRouteM: 100, accuracyM: 10, now: start), isFalse);
      expect(gate.shouldReroute(offRouteM: 100, accuracyM: 10, now: start), isTrue);
    });

    test('GPS kém không kết luận gì', () {
      final RerouteGate gate = RerouteGate();
      expect(gate.shouldReroute(offRouteM: 500, accuracyM: 80, now: start), isFalse);
      expect(gate.shouldReroute(offRouteM: 500, accuracyM: 80, now: start), isFalse);
    });

    test('cách lần xin trước tối thiểu 30 giây', () {
      final RerouteGate gate = RerouteGate()..markRequested(start);
      expect(gate.shouldReroute(offRouteM: 100, accuracyM: 10, now: start), isFalse);
      expect(gate.shouldReroute(offRouteM: 100, accuracyM: 10, now: start.add(const Duration(seconds: 29))), isFalse);
      expect(gate.shouldReroute(offRouteM: 100, accuracyM: 10, now: start.add(const Duration(seconds: 30))), isTrue);
    });
  });
}
