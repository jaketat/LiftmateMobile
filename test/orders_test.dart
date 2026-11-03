// Đọc dữ liệu đơn hàng theo đúng DTO của backend, và nút đổi bước theo allowedActions
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liftmate_mobile/features/customers/customer_detail_screen.dart' show orderStatusColor;
import 'package:liftmate_mobile/features/orders/order_actions.dart';
import 'package:liftmate_mobile/features/orders/order_detail_screen.dart' show orderShowsTrips;
import 'package:liftmate_mobile/features/orders/orders_api.dart';

Map<String, dynamic> detailJson() {
  return <String, dynamic>{
    'publicId': 'o1',
    'orderCode': 'DH-202610-0001',
    'customer': <String, dynamic>{'publicId': 'c1', 'customerCode': 'KH-1', 'customerName': 'Thép Hải Bắc', 'phone': '0900000000', 'email': null},
    'pickupAddress': 'A',
    'deliveryAddress': 'B',
    'scheduledDate': '2026-10-01',
    'scheduledEndDate': '2026-10-02',
    'stops': <Map<String, dynamic>>[
      <String, dynamic>{'publicId': 's1', 'sequence': 1, 'kind': 'Pickup', 'address': 'A', 'latitude': 20.9, 'longitude': 106.6, 'contactName': 'Mạnh', 'contactPhone': '0932', 'note': null, 'unloadMethod': null},
      <String, dynamic>{'publicId': 's2', 'sequence': 2, 'kind': 'Delivery', 'address': 'B', 'latitude': null, 'longitude': null, 'contactName': null, 'contactPhone': null, 'note': null, 'unloadMethod': 'Crane'},
    ],
    'workDays': <Map<String, dynamic>>[
      <String, dynamic>{'workDate': '2026-10-01', 'startTime': '07:30:00', 'endTime': '17:00:00', 'isOvernight': false, 'note': null},
    ],
    'status': 'InProgress',
    'totalDistanceKm': 125.5,
    'estimatedFuelCost': 1200000,
    'tollCost': 300000,
    'quotedAmount': 15000000,
    'extraCharges': <Map<String, dynamic>>[
      <String, dynamic>{'publicId': 'e1', 'description': 'Thêm giờ cẩu', 'amount': 500000, 'confirmedWithCustomer': false, 'confirmedByName': null, 'confirmedAt': null, 'createdByName': 'An', 'createdAt': '2026-10-01T03:00:00Z'},
    ],
    'extraChargesTotal': 500000,
    'totalAmount': 15500000,
    'finalAmount': null,
    'routePolyline': null,
    'routeWarning': 'Tuyến ước tính',
    'cancelReason': null,
    'notes': null,
    'createdAt': '2026-09-30T03:00:00Z',
    'cargos': <Map<String, dynamic>>[
      <String, dynamic>{'publicId': 'k1', 'cargoName': 'Máy tiện', 'quantity': 2, 'weightKg': 1500.5, 'lengthMm': 2000, 'widthMm': 1000, 'heightMm': 1500, 'isFragile': true, 'doNotStack': false},
    ],
    'totalCargosCount': 2,
    'totalWeightKg': 3001,
    'totalVolumeM3': 6,
    'allowedActions': <String>['finish', 'cancel', 'somethingNew'],
    'oversizeWarnings': <Map<String, dynamic>>[
      <String, dynamic>{'code': 'OVER_CLEARANCE', 'message': 'Quá cao', 'legalBasis': 'TT 39', 'requiresPermit': true},
    ],
    'tollClassAssumed': true,
  };
}

void main() {
  test('mục trong menu "…" có biểu tượng, hành động nguy hiểm được đánh dấu', () {
    final List<OrderActionDef> more = allowedOrderActions(<String>['start', 'reopenQuote', 'cancel'], secondary: true);
    expect(more.map((OrderActionDef def) => def.key), <String>['reopenQuote', 'cancel']);
    expect(more.every((OrderActionDef def) => def.symbol != null), isTrue);
    expect(more.last.danger, isTrue);
  });

  test('màn chuyến chạy mở từ khi khách xác nhận, trước đó thì chưa', () {
    for (final String status in <String>['Draft', 'Quoted', 'Cancelled']) {
      expect(orderShowsTrips(status), isFalse, reason: status);
    }
    for (final String status in <String>['CustomerConfirmed', 'Scheduled', 'InProgress', 'AwaitingFinalization', 'Finalized', 'Invoiced']) {
      expect(orderShowsTrips(status), isTrue, reason: status);
    }
  });

  test('Mỗi trạng thái đơn một màu riêng, trạng thái lạ về xám như Nháp', () {
    const List<String> statuses = <String>['Draft', 'Quoted', 'CustomerConfirmed', 'Scheduled', 'InProgress', 'AwaitingFinalization', 'Finalized', 'Invoiced', 'Cancelled'];
    expect(statuses.map(orderStatusColor).toSet().length, statuses.length);
    expect(orderStatusColor('SomethingNew'), orderStatusColor('Draft'));
  });

  test('Đọc đủ chi tiết đơn, số thập phân và số nguyên đều được', () {
    final OrderDetail order = OrderDetail.fromJson(detailJson());
    expect(order.customerName, 'Thép Hải Bắc');
    expect(order.stops.length, 2);
    expect(order.stops.first.latitude, 20.9);
    expect(order.stops.last.latitude, isNull);
    expect(order.hasCoordinates, isTrue);
    expect(order.workDays.single.startTime, '07:30:00');
    expect(order.cargos.single.weightKg, 1500.5);
    expect(order.extraCharges.single.confirmedWithCustomer, isFalse);
    expect(order.totalAmount, 15500000);
    expect(order.oversizeWarnings.single.isDanger, isTrue);
    expect(order.tollClassAssumed, isTrue);
  });

  test('Trường tùy chọn vắng mặt vẫn đọc được', () {
    final OrderDetail order = OrderDetail.fromJson(<String, dynamic>{
      'publicId': 'o2',
      'orderCode': 'DH-2',
      'status': 'Draft',
      'createdAt': '2026-09-30T03:00:00Z',
    });
    expect(order.allowedActions, isEmpty);
    expect(order.stops, isEmpty);
    expect(order.quotedAmount, isNull);
    expect(order.hasCoordinates, isFalse);
  });

  test('Dòng danh sách ưu tiên số đã chốt', () {
    OrderSummary row(num? quoted, num? finalAmount) => OrderSummary.fromJson(<String, dynamic>{
          'publicId': 'o',
          'orderCode': 'DH',
          'customerName': 'K',
          'pickupAddress': 'A',
          'deliveryAddress': 'B',
          'scheduledDate': null,
          'scheduledEndDate': null,
          'status': 'Draft',
          'quotedAmount': quoted,
          'finalAmount': finalAmount,
        });
    expect(row(100, null).amount, 100);
    expect(row(100, 120).amount, 120);
    expect(row(null, null).amount, isNull);
  });

  test('Nút theo allowedActions, chia nút chính và menu, bỏ hành động lạ', () {
    const List<String> allowed = <String>['cancel', 'finish', 'somethingNew'];
    expect(allowedOrderActions(allowed, secondary: false).map((OrderActionDef def) => def.key), <String>['finish']);
    expect(allowedOrderActions(allowed, secondary: true).map((OrderActionDef def) => def.key), <String>['cancel']);
  });

  test('Mọi hành động của backend đều có đường dẫn, hủy và xuất hóa đơn bắt nhập', () {
    final Map<String, OrderActionDef> defs = <String, OrderActionDef>{for (final OrderActionDef def in orderActionDefs) def.key: def};
    expect(defs.keys.toSet(), <String>{'sendQuote', 'confirm', 'reopenQuote', 'schedule', 'start', 'finish', 'finalize', 'invoice', 'cancel'});
    expect(defs['sendQuote']!.path, 'send-quote');
    expect(defs['reopenQuote']!.path, 'reopen-quote');
    expect(defs['cancel']!.required, isTrue);
    expect(defs['invoice']!.required, isTrue);
    expect(defs['confirm']!.required, isFalse);
  });

  test('Ô tiền: thêm dấu chấm nghìn, đọc lại đúng số', () {
    final MoneyInputFormatter formatter = MoneyInputFormatter();
    final String text = formatter.formatEditUpdate(TextEditingValue.empty, const TextEditingValue(text: '1500000a')).text;
    expect(text, '1.500.000');
    expect(parseMoneyInput(text), 1500000);
    expect(parseMoneyInput(''), isNull);
  });
}
