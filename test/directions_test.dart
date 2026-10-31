// Test chỉ đường theo tuyến đã lưu: giải mã tuyến, vị trí trên tuyến, chỗ rẽ và hướng rẽ (BR-TRK-011).
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

  test('chuyến đọc được tuyến đã lưu; không có thì null', () {
    Map<String, dynamic> trip() => <String, dynamic>{
          'publicId': 'a',
          'orderCode': 'DH',
          'orderStatus': 'Scheduled',
          'customerName': 'K',
          'startAt': '2026-10-31T01:00:00Z',
          'endAt': '2026-10-31T05:00:00Z',
          'myRole': 'MainDriver',
        };
    expect(MyTrip.fromJson(trip()).routePolyline, isNull);
    expect(MyTrip.fromJson(trip()..['routePolyline'] = null).routePolyline, isNull);
    expect(MyTrip.fromJson(trip()..['routePolyline'] = 'abc').routePolyline, 'abc');
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
      expect(track.maneuverPoints, isEmpty);
    });
  });

  group('tìm chỗ rẽ trên tuyến', () {
    test('chỉ lấy chỗ rẽ thật, bỏ đoạn hơi chếch', () {
      final RouteTrack track = RouteTrack(<LatLng>[
        LatLng(21.0, 105.8),
        LatLng(21.009, 105.8),
        LatLng(21.018, 105.804), // chếch nhẹ
        LatLng(21.018, 105.814), // rẽ phải ở điểm trước
        LatLng(21.027, 105.814), // rẽ trái ở điểm trước
      ]);
      expect(track.maneuverPoints, <int>[2, 3]);
    });

    test('các điểm liền nhau trong 30 m tính là một chỗ rẽ', () {
      final RouteTrack track = RouteTrack(<LatLng>[
        LatLng(21.0, 105.8),
        LatLng(21.009, 105.8),
        LatLng(21.0091, 105.8001),
        LatLng(21.0091, 105.81),
      ]);
      expect(track.maneuverPoints.length, 1);
    });
  });

  group('vị trí trên tuyến', () {
    final RouteTrack track = turning(0, 0.01);

    test('xe trên tuyến: không lệch, còn lại đúng phần chưa đi', () {
      final RouteProgress start = track.progress(LatLng(21.0, 105.8));
      expect(start.segment, 0);
      expect(start.offRouteM, lessThan(1));
      expect(start.remainingM, closeTo(track.totalM, 1));
    });

    test('xe lệch sang ngang: đo đúng khoảng lệch', () {
      expect(track.progress(LatLng(21.004, 105.801)).offRouteM, closeTo(104, 5));
    });

    test('vị trí không làm đổi tuyến: xe ở rất xa vẫn tính từ đầu tuyến', () {
      final RouteProgress far = track.progress(LatLng(20.0, 105.8));
      expect(far.segment, 0);
      expect(far.offRouteM, greaterThan(100000));
      expect(far.remainingM, closeTo(track.totalM, 1));
      expect(track.nextManeuver(far).turn, TurnKind.right);
    });
  });

  test('đọc tuyến từ vị trí xe: số dạng chuỗi, đường không tên', () {
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
    expect(parsed.steps.map((DirectionStep step) => step.road), <String?>['Quốc Lộ 46', 'Đường X', null]);
    expect(parsed.steps.first.pointIndex, 49);
  });

  test('tuyến có chỉ dẫn: lấy đúng các bước và tên đường, hướng rẽ vẫn tính từ hình dạng', () {
    final RouteTrack track = RouteTrack(
      <LatLng>[LatLng(21.0, 105.8), LatLng(21.009, 105.8), LatLng(21.009, 105.81), LatLng(21.018, 105.81)],
      stepRoads: const <int, String?>{0: null, 1: 'Quốc Lộ 5', 2: 'Đường B', 3: null},
    );
    expect(track.maneuverPoints, <int>[1, 2]);
    final NextManeuver next = track.nextManeuver(track.progress(LatLng(21.002, 105.8)));
    expect(next.turn, TurnKind.right);
    expect(next.road, 'Quốc Lộ 5');
  });

  group('khi nào xin tuyến từ vị trí xe', () {
    final DateTime now = DateTime(2026, 11, 1, 8);

    test('xe trên tuyến đã lưu thì không xin, không tốn lượt', () {
      expect(wantsLiveRoute(offRouteM: 50, accuracyM: 10, now: now), isFalse);
      expect(wantsLiveRoute(offRouteM: offSavedRouteM, accuracyM: 10, now: now), isFalse);
    });

    test('xe ở xa tuyến thì xin', () {
      expect(wantsLiveRoute(offRouteM: 100000, accuracyM: 10, now: now), isTrue);
    });

    test('GPS kém thì chưa kết luận', () {
      expect(wantsLiveRoute(offRouteM: 100000, accuracyM: 500, now: now), isFalse);
    });

    test('vừa xin lỗi thì đợi hết thời gian chờ mới xin lại', () {
      final DateTime retryAt = now.add(const Duration(minutes: 5));
      expect(wantsLiveRoute(offRouteM: 100000, accuracyM: 10, now: now, retryAt: retryAt), isFalse);
      expect(wantsLiveRoute(offRouteM: 100000, accuracyM: 10, now: retryAt, retryAt: retryAt), isTrue);
    });
  });

  group('khi nào xin lại tuyến khi đang đi theo tuyến từ vị trí xe', () {
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

  test('mô phỏng cả tuyến: rẽ phải, rẽ trái rồi tới điểm cuối', () {
    final RouteTrack track = RouteTrack(<LatLng>[
      LatLng(21.0, 105.8),
      LatLng(21.009, 105.8),
      LatLng(21.009, 105.81),
      LatLng(21.018, 105.81),
    ]);
    NextManeuver at(double lat, double lng) => track.nextManeuver(track.progress(LatLng(lat, lng)));

    final NextManeuver first = at(21.002, 105.8);
    expect(first.turn, TurnKind.right);
    expect(first.distanceM, closeTo(778, 10));

    final NextManeuver second = at(21.009, 105.805);
    expect(second.turn, TurnKind.left);
    expect(second.distanceM, closeTo(519, 10));

    final NextManeuver last = at(21.012, 105.81);
    expect(last.turn, isNull);
    expect(last.distanceM, closeTo(667, 10));

    expect(track.progress(LatLng(21.018, 105.81)).remainingM, closeTo(0, 1));
  });
}
