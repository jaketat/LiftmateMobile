// Test luật app tài xế (Người 2). Cùng các trường hợp với web src/features/driver/milestones.test.ts.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liftmate_mobile/core/i18n.dart';
import 'package:liftmate_mobile/features/driver/driver_api.dart';
import 'package:liftmate_mobile/features/driver/location_gate.dart';
import 'package:liftmate_mobile/features/driver/trip_logic.dart';

Map<String, dynamic> stopJson(int sequence, String kind) => <String, dynamic>{
      'sequence': sequence,
      'kind': kind,
      'address': 'KCN Tân Tạo',
      'latitude': null,
      'longitude': null,
      'contactName': null,
      'contactPhone': null,
      'note': null,
    };

Map<String, dynamic> milestoneJson(int stopSequence, String kind, {bool canUndo = false}) => <String, dynamic>{
      'publicId': '$stopSequence$kind',
      'stopSequence': stopSequence,
      'kind': kind,
      'recordedAt': '2026-10-27T01:00:00Z',
      'receivedAt': '2026-10-27T01:00:02Z',
      'latitude': null,
      'longitude': null,
      'accuracyM': null,
      'canUndo': canUndo,
    };

MyTrip trip({
  String id = 't1',
  String startAt = '2026-10-27T01:00:00Z',
  String endAt = '2026-10-27T05:00:00Z',
  List<Map<String, dynamic>>? stops,
  List<Map<String, dynamic>> milestones = const <Map<String, dynamic>>[],
  Map<String, dynamic>? nextAction = const <String, dynamic>{'stopSequence': 1, 'kind': 'Arrived'},
  String myRole = 'MainDriver',
  String baseType = 'Truck',
  bool trackingActive = true,
  String orderStatus = 'Scheduled',
}) {
  return MyTrip.fromJson(<String, dynamic>{
    'publicId': id,
    'orderCode': 'DH-202610-0012',
    'orderStatus': orderStatus,
    'customerName': 'Cơ khí Minh Phát',
    'startAt': startAt,
    'endAt': endAt,
    'note': null,
    'myRole': myRole,
    'myVehiclePublicId': 'v1',
    'vehicles': <dynamic>[
      <String, dynamic>{'publicId': 'v1', 'plateNumber': '51C-900.01', 'vehicleType': 'Xe tải', 'baseType': baseType, 'maxPayloadKg': '15000'},
    ],
    'crew': <dynamic>[],
    'stops': stops ?? <Map<String, dynamic>>[stopJson(1, 'Pickup'), stopJson(2, 'Delivery')],
    'cargoKg': '3630',
    'canUploadDocuments': true,
    'milestones': milestones,
    'nextAction': nextAction,
    'trackingActive': trackingActive,
  });
}

void main() {
  // Chữ trên giao diện đọc từ assets/i18n/vi.json (như khi máy đặt tiếng Việt)
  setUpAll(() {
    final Map<String, dynamic> raw = jsonDecode(File('assets/i18n/vi.json').readAsStringSync()) as Map<String, dynamic>;
    I18n.useStrings(raw.map((String key, dynamic value) => MapEntry<String, String>(key, value.toString())));
  });

  test('đọc chuyến: số dạng chuỗi, điểm xếp theo thứ tự', () {
    final MyTrip t = trip(stops: <Map<String, dynamic>>[stopJson(2, 'Delivery'), stopJson(1, 'Pickup')]);
    expect(t.cargoKg, 3630);
    expect(t.stops.first.sequence, 1);
    expect(t.myVehicle?.displayName, '51C-900.01');
  });

  test('chữ nút theo loại điểm', () {
    expect(milestoneActionLabel('Arrived', 'Pickup'), 'Đã đến điểm bốc');
    expect(milestoneActionLabel('Arrived', 'Delivery'), 'Đã đến điểm trả');
    expect(milestoneActionLabel('Departed', 'Pickup'), 'Bắt đầu chạy');
    expect(milestoneActionLabel('Departed', 'Delivery'), 'Rời điểm');
    expect(milestoneDoneLabel('Departed', 'Pickup'), 'Bắt đầu chạy');
    expect(milestoneDoneLabel('Departed', 'Delivery'), 'Đã rời');
  });

  test('thứ tự mốc trong một điểm', () {
    expect(stepsForStop('Pickup'), <String>['Arrived', 'Loaded', 'Departed']);
    expect(stepsForStop('Delivery'), <String>['Arrived', 'Unloaded', 'Departed']);
    expect(stepsForStop('Via'), <String>['Arrived', 'Departed']);
  });

  test('trạng thái điểm theo mốc', () {
    final TripStop pickup = trip().stops.first;
    expect(stopState(trip(), pickup), StopState.todo);
    expect(stopState(trip(milestones: <Map<String, dynamic>>[milestoneJson(1, 'Arrived')]), pickup), StopState.active);
    expect(
      stopState(
          trip(milestones: <Map<String, dynamic>>[
            milestoneJson(1, 'Arrived'),
            milestoneJson(1, 'Loaded'),
            milestoneJson(1, 'Departed'),
          ]),
          pickup),
      StopState.done,
    );
    expect(nextStepAtStop(trip(milestones: <Map<String, dynamic>>[milestoneJson(1, 'Arrived')]), pickup), 'Loaded');
  });

  test('ô đồng hồ chỉ khi lái chính rời điểm trả cuối', () {
    final List<Map<String, dynamic>> done = <Map<String, dynamic>>[
      milestoneJson(1, 'Departed'),
      milestoneJson(2, 'Arrived'),
      milestoneJson(2, 'Unloaded'),
    ];
    const Map<String, dynamic> leave2 = <String, dynamic>{'stopSequence': 2, 'kind': 'Departed'};
    // Còn điểm trả 3
    expect(
      meterFields(trip(
        stops: <Map<String, dynamic>>[stopJson(1, 'Pickup'), stopJson(2, 'Delivery'), stopJson(3, 'Delivery')],
        milestones: done,
        nextAction: leave2,
      )),
      isNull,
    );
    expect(meterFields(trip(milestones: done, nextAction: leave2)), (km: true, hours: false));
    expect(meterFields(trip(milestones: done, nextAction: leave2, myRole: 'Assistant')), isNull);
    expect(meterFields(trip(milestones: done, nextAction: leave2, baseType: 'MobileCraneWheeled')), (km: true, hours: true));
    expect(meterFields(trip(milestones: done, nextAction: leave2, baseType: 'Trailer')), isNull);
  });

  test('đến điểm khác và hoàn tác', () {
    final MyTrip t = trip(
      stops: <Map<String, dynamic>>[stopJson(1, 'Pickup'), stopJson(2, 'Via'), stopJson(3, 'Delivery')],
      milestones: <Map<String, dynamic>>[milestoneJson(1, 'Arrived', canUndo: true)],
      nextAction: const <String, dynamic>{'stopSequence': 1, 'kind': 'Loaded'},
    );
    expect(skippableStops(t).map((TripStop s) => s.sequence), <int>[2, 3]);
    expect(undoableMilestone(t)?.kind, 'Arrived');
  });

  test('câu khi chưa bấm mốc được', () {
    final DateTime now = DateTime.parse('2026-10-27T00:00:00Z');
    expect(milestoneBlockedText(trip(trackingActive: false, orderStatus: 'CustomerConfirmed'), now), contains('chưa được chốt lịch'));
    expect(milestoneBlockedText(trip(trackingActive: false, startAt: '2026-10-29T01:00:00Z', endAt: '2026-10-29T05:00:00Z'), now),
        contains('Chưa đến giờ'));
    expect(milestoneBlockedText(trip(trackingActive: false, startAt: '2026-10-20T01:00:00Z', endAt: '2026-10-20T05:00:00Z'), now),
        contains('đã kết thúc'));
    expect(milestoneBlockedText(trip(nextAction: null), now), contains('Đã hoàn tất mọi điểm'));
    expect(milestoneBlockedText(trip(), now), isNull);
  });

  test('chia chuyến Hôm nay / Sắp tới / Đã qua, chuyến nổi bật', () {
    final DateTime now = DateTime.now();
    String at(Duration offset) => now.add(offset).toUtc().toIso8601String();
    final List<MyTrip> trips = <MyTrip>[
      trip(id: 'qua', startAt: at(const Duration(days: -3)), endAt: at(const Duration(days: -3, hours: 4)), nextAction: null, trackingActive: false),
      trip(id: 'toi', startAt: at(const Duration(days: 3)), endAt: at(const Duration(days: 3, hours: 4)), trackingActive: false),
      trip(id: 'nay', startAt: at(const Duration(minutes: -30)), endAt: at(const Duration(hours: 3))),
    ];
    final TripGroups groups = groupTrips(trips, now);
    expect(groups.today.map((MyTrip t) => t.publicId), <String>['nay']);
    expect(groups.upcoming.map((MyTrip t) => t.publicId), <String>['toi']);
    expect(groups.past.map((MyTrip t) => t.publicId), <String>['qua']);
    expect(featuredTrip(groups)?.publicId, 'nay');
  });

  test('gửi mốc: tọa độ đủ cả hai mới gửi, recordedAt chỉ khi gửi bù', () {
    final MilestoneRequest only = MilestoneRequest(stopSequence: 1, kind: 'Arrived', latitude: 10.75);
    expect(only.toJson().containsKey('latitude'), isFalse);
    final MilestoneRequest full = MilestoneRequest(stopSequence: 1, kind: 'Arrived', latitude: 10.75, longitude: 106.6);
    expect(full.toJson()['longitude'], 106.6);
    expect(full.toJson().containsKey('recordedAt'), isFalse);
    expect(full.asRetry().toJson().containsKey('recordedAt'), isTrue);
    expect(full.asRetry().idempotencyKey, full.idempotencyKey);
  });

  test('đang làm chuyến dở thì khóa nút tắt chia sẻ vị trí', () {
    // Chưa bấm mốc nào: chưa khóa
    expect(tripInProgress(<MyTrip>[trip()]), isNull);
    // Đã bấm mốc, còn việc, trong khung chuyến: khóa
    expect(tripInProgress(<MyTrip>[trip(milestones: <Map<String, dynamic>>[milestoneJson(1, 'Arrived')])])?.publicId, 't1');
    // Xong mọi điểm: mở khóa
    expect(tripInProgress(<MyTrip>[trip(milestones: <Map<String, dynamic>>[milestoneJson(1, 'Arrived')], nextAction: null)]), isNull);
    // Ngoài khung chuyến: mở khóa
    expect(
      tripInProgress(<MyTrip>[trip(milestones: <Map<String, dynamic>>[milestoneJson(1, 'Arrived')], trackingActive: false)]),
      isNull,
    );
    expect(locationGateText(LocationGate.serviceOff), contains('định vị'));
  });
}
