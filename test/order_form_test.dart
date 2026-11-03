// Luật form tạo đơn: khớp backend và web (slice-03 mục 2.3)
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:liftmate_mobile/features/orders/order_form.dart';

OrderFormData validForm() {
  final OrderFormData form = OrderFormData();
  form.customerId = 'c1';
  form.customerName = 'Khách';
  form.stops = <StopDraft>[
    StopDraft(kind: 'Pickup', address: 'A', latitude: 20.9, longitude: 106.6),
    StopDraft(kind: 'Delivery', address: 'B', latitude: 20.8, longitude: 106.7),
  ];
  return form;
}

CargoDraft validCargo() => CargoDraft(cargoName: 'Máy', quantity: '2', weightKg: '1500,5', lengthMm: '2000', widthMm: '1000', heightMm: '1500');

void main() {
  test('Số nguyên không nhận dấu chấm vì "25.000" có thể là 25 hay 25000', () {
    expect(parseNumberInput('25000', integer: true), 25000);
    expect(parseNumberInput('25.000', integer: true)!.isNaN, isTrue);
    expect(parseNumberInput('', integer: true), isNull);
    expect(parseNumberInput('12,5', integer: false), 12.5);
    expect(parseNumberInput('12.5', integer: false), 12.5);
    expect(parseNumberInput('abc', integer: false)!.isNaN, isTrue);
  });

  test('Số điện thoại theo luật CustomerPhone của backend', () {
    expect(isValidCustomerPhone('0932256276'), isTrue);
    expect(isValidCustomerPhone('093 225 6276'), isTrue);
    expect(isValidCustomerPhone('+84932256276'), isTrue);
    expect(isValidCustomerPhone('84932256276'), isTrue);
    expect(isValidCustomerPhone('02438123456'), isTrue);
    expect(isValidCustomerPhone('0132256276'), isFalse);
    expect(isValidCustomerPhone('093225627'), isFalse);
    expect(isValidCustomerPhone(''), isFalse);
  });

  test('Lưu nháp chỉ cần khách và điểm dừng', () {
    expect(validForm().validate(forQuote: false), isEmpty);
  });

  test('Gửi báo giá đòi đủ kiện, ngày làm, giá', () {
    final Map<String, String> errors = validForm().validate(forQuote: true);
    expect(errors.keys.toSet(), <String>{'cargos', 'days', 'quoted'});

    final OrderFormData form = validForm()
      ..cargos = <CargoDraft>[validCargo()]
      ..workDays = <WorkDayDraft>[WorkDayDraft(workDate: '2026-11-05')]
      ..quotedAmount = 1000;
    expect(form.validate(forQuote: true), isEmpty);
  });

  test('Luật thứ tự điểm dừng', () {
    final OrderFormData form = validForm();
    form.stops = <StopDraft>[StopDraft(kind: 'Delivery', address: 'A'), StopDraft(kind: 'Pickup', address: 'B')];
    expect(form.validate(forQuote: false).containsKey('stops'), isTrue);

    form.stops = <StopDraft>[StopDraft(kind: 'Pickup', address: 'A'), StopDraft(kind: 'Delivery', address: 'B'), StopDraft(kind: 'Via', address: 'C')];
    expect(form.validate(forQuote: false).containsKey('stops'), isTrue);

    form.stops = <StopDraft>[StopDraft(kind: 'Pickup', address: 'A'), StopDraft(kind: 'Pickup', address: 'B')];
    expect(form.validate(forQuote: false).containsKey('stops'), isTrue);
  });

  test('Điểm thiếu địa chỉ hoặc số liên hệ sai thì báo đúng điểm; điểm đi qua không xét số', () {
    final StopDraft pickup = StopDraft(kind: 'Pickup', contactPhone: '123');
    final StopDraft via = StopDraft(kind: 'Via', address: 'C', contactPhone: '123');
    final StopDraft delivery = StopDraft(kind: 'Delivery', address: 'B');
    final OrderFormData form = validForm()..stops = <StopDraft>[pickup, via, delivery];
    final Map<String, String> errors = form.validate(forQuote: false);
    expect(errors.containsKey('stop.${pickup.key}'), isTrue);
    expect(errors.containsKey('stop.${pickup.key}.phone'), isTrue);
    expect(errors.containsKey('stop.${via.key}.phone'), isFalse);
  });

  test('Ngày làm: thiếu ngày, trùng ngày, giờ trùng nhau; giờ kết thúc nhỏ hơn là ca qua đêm hợp lệ', () {
    final WorkDayDraft empty = WorkDayDraft();
    final WorkDayDraft first = WorkDayDraft(workDate: '2026-11-05');
    final WorkDayDraft duplicate = WorkDayDraft(workDate: '2026-11-05');
    final WorkDayDraft sameTime = WorkDayDraft(workDate: '2026-11-06', startTime: '08:00', endTime: '08:00');
    final WorkDayDraft overnight = WorkDayDraft(workDate: '2026-11-07', startTime: '22:00', endTime: '05:00');
    final OrderFormData form = validForm()..workDays = <WorkDayDraft>[empty, first, duplicate, sameTime, overnight];
    final Map<String, String> errors = form.validate(forQuote: false);
    expect(errors.containsKey('day.${empty.key}'), isTrue);
    expect(errors.containsKey('day.${first.key}'), isFalse);
    expect(errors.containsKey('day.${duplicate.key}'), isTrue);
    expect(errors.containsKey('day.${sameTime.key}'), isTrue);
    expect(errors.containsKey('day.${overnight.key}'), isFalse);
    expect(overnight.toJson()['endTime'], '05:00:00');
  });

  test('Kiện: kiểm tra từng ô, bồn trụ tròn bắt buộc cao giá đỡ', () {
    expect(validCargo().validate(), isEmpty);
    final Map<String, String> errors = CargoDraft(quantity: '0', weightKg: '-1', lengthMm: '2.000').validate();
    expect(errors.keys.toSet(), <String>{'cargoName', 'quantity', 'weightKg', 'lengthMm', 'widthMm', 'heightMm'});
    expect(validCargo().toJson()['weightKg'], 1500.5);

    final CargoDraft cylinder = validCargo()..supportType = 'Cylinder';
    expect(cylinder.validate().containsKey('saddleHeightMm'), isTrue);
    cylinder.saddleHeightMm = '300';
    expect(cylinder.validate(), isEmpty);
    expect(cylinder.toJson()['saddleHeightMm'], 300);
    expect((validCargo()
          ..supportType = 'Cylinder'
          ..canLieDown = true)
        .toJson()['canLieDown'], isFalse);
  });

  test('Kiện AI đọc: ô chưa chắc và ô tin không ghi bị chặn tới khi xác nhận', () {
    Map<String, dynamic> cell(Object? value, {bool confirm = false, String? raw}) => <String, dynamic>{'value': value, 'raw': raw, 'needsConfirmation': confirm, 'reason': null};
    final CargoDraft cargo = CargoDraft.fromAi(<String, dynamic>{
      'cargoName': 'Máy ép',
      'quantity': cell(2),
      'weightKg': cell(8000, confirm: true, raw: '8 tấn'),
      'lengthMm': cell(3000),
      'widthMm': cell(null),
      'heightMm': cell(2000),
      'isFragile': true,
      'doNotStack': false,
      'rotationAllowed': true,
      'canLieDown': false,
      'supportType': 'Flat',
      'sourceText': '2 máy ép 8 tấn',
      'issues': <String>['Thiếu chiều rộng'],
    });
    expect(cargo.weightKg, '8000');
    expect(cargo.aiFlags.keys.toSet(), <String>{'weightKg', 'widthMm'});
    expect(cargo.aiFlags['weightKg']!.raw, '8 tấn');
    expect(cargo.aiRaws['weightKg'], '8 tấn');
    expect(cargo.validate().containsKey('weightKg'), isTrue);

    cargo.aiFlags.remove('weightKg');
    cargo.aiFlags.remove('widthMm');
    cargo.widthMm = '1500';
    expect(cargo.validate(), isEmpty);
  });

  test('Dữ liệu gửi đi: khách quen hoặc khách mới, điểm đi qua bỏ liên hệ, cách dỡ chỉ cho điểm trả', () {
    final OrderFormData form = validForm();
    form.stops = <StopDraft>[
      StopDraft(kind: 'Pickup', address: ' A ', contactName: 'An', contactPhone: '0932256276'),
      StopDraft(kind: 'Via', address: 'B', contactName: 'Bỏ', contactPhone: '0932256276'),
      StopDraft(kind: 'Delivery', address: 'C'),
    ];
    final Map<String, dynamic> json = form.toJson();
    expect(json['customerPublicId'], 'c1');
    expect(json.containsKey('quickCustomerName'), isFalse);
    final List<Map<String, dynamic>> stops = json['stops'] as List<Map<String, dynamic>>;
    expect(stops[0]['address'], 'A');
    expect(stops[0]['unloadMethod'], isNull);
    expect(stops[1]['contactName'], isNull);
    expect(stops[1]['contactPhone'], isNull);
    expect(stops[2]['unloadMethod'], 'Crane');

    form
      ..isNewCustomer = true
      ..customerName = 'Mới'
      ..customerPhone = '0932256276';
    final Map<String, dynamic> quick = form.toJson();
    expect(quick.containsKey('customerPublicId'), isFalse);
    expect(quick['quickCustomerName'], 'Mới');
    expect(quick['quickCustomerPhone'], '0932256276');
  });

  test('Khách mới: bắt nhập tên và số đúng', () {
    final OrderFormData form = validForm()
      ..isNewCustomer = true
      ..customerName = ''
      ..customerPhone = '0932256276';
    expect(form.validate(forQuote: false).containsKey('customer'), isTrue);
    form.customerName = 'Mới';
    expect(form.validate(forQuote: false).containsKey('customer'), isFalse);
    form.customerPhone = '123';
    expect(form.validate(forQuote: false).containsKey('customer'), isTrue);
  });

  test('Ước tính tuyến chỉ gọi khi mọi điểm có tọa độ', () {
    final OrderFormData form = validForm();
    final Map<String, dynamic> request = form.routeRequest()!;
    expect(request['originLatitude'], 20.9);
    expect(request['destinationLongitude'], 106.7);
    expect(request['waypoints'], isEmpty);

    form.stops.insert(1, StopDraft(kind: 'Via', address: 'X', latitude: 21, longitude: 106));
    expect((form.routeRequest()!['waypoints'] as List<dynamic>).length, 1);

    form.stops.add(StopDraft(kind: 'Delivery', address: 'Y'));
    expect(form.routeRequest(), isNull);
  });

  test('Tóm tắt kiện tính theo số lượng, bỏ qua ô chưa nhập', () {
    final OrderFormData form = validForm()..cargos = <CargoDraft>[validCargo(), CargoDraft(cargoName: 'Tủ', quantity: '3', weightKg: '')];
    expect(form.totalPieces, 5);
    expect(form.totalKg, 3001);
  });

  test('Nháp đọc lại đủ mọi ô, ở dạng người dùng đã gõ', () {
    final OrderFormData form = validForm()
      ..isNewCustomer = true
      ..customerPhone = '0932256276'
      ..workDays = <WorkDayDraft>[WorkDayDraft(workDate: '2026-11-05', startTime: '22:00', endTime: '05:00', note: 'Ca đêm')]
      ..cargos = <CargoDraft>[
        CargoDraft(cargoName: 'Bồn', quantity: '', weightKg: '12,5', lengthMm: '2.000', isFragile: true, doNotStack: true, rotationAllowed: false, supportType: 'Cylinder', saddleHeightMm: '300')
      ]
      ..quotedAmount = 1500000
      ..operatingProfile = 'Mountain'
      ..notes = 'Ghi chú';
    form.stops.first
      ..contactName = 'An'
      ..contactPhone = '123'
      ..note = 'Cổng 2';
    form.stops.last.unloadMethod = 'ForkliftFromRear';
    final Map<String, dynamic> saved = jsonDecode(jsonEncode(form.toDraft())) as Map<String, dynamic>;
    final OrderFormData back = OrderFormData.fromDraft(saved);
    expect(back.toDraft(), form.toDraft());
    expect(back.stops.first.latitude, 20.9);
    // Khóa ô cấp lại, không trùng với kiện đang có
    expect(back.cargos.first.key, isNot(form.cargos.first.key));
  });

  test('Chỉ nhập liên hệ, chưa có địa chỉ cũng tính là có dữ liệu cần giữ', () {
    final OrderFormData form = OrderFormData();
    form.stops.last.contactPhone = '0932256276';
    expect(form.isDirty, isTrue);
  });

  test('Form mới chưa nhập gì thì không cần giữ nháp', () {
    final OrderFormData form = OrderFormData();
    expect(form.isDirty, isFalse);
    form.stops.first.address = 'A';
    expect(form.isDirty, isTrue);
  });
}
