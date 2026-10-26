// Gọi API chốt đơn và hóa đơn (doc mục 3.14).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/call.dart';

// Khoản phát sinh của đơn
class ExtraCharge {
  // chargeId
  final String id;
  final String description;
  final num amount;
  // true: khách đã đồng ý khoản này
  final bool confirmedWithCustomer;

  ExtraCharge({required this.id, required this.description, required this.amount, required this.confirmedWithCustomer});

  factory ExtraCharge.fromJson(Map<String, dynamic> json) {
    return ExtraCharge(
      id: (json['publicId'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      amount: (json['amount'] as num?) ?? 0,
      confirmedWithCustomer: (json['confirmedWithCustomer'] as bool?) ?? false,
    );
  }
}

// Phần của đơn mà màn chốt đơn cần (cùng API chi tiết đơn của người 2, chỉ lấy vài trường)
class CloseOrder {
  // InProgress, AwaitingFinalization, Finalized, Invoiced...
  final String status;
  // Các nút server cho bấm lúc này. Rỗng: app dựa theo status
  final List<String> allowedActions;
  final String orderCode;
  final String customerName;
  final num quotedAmount;
  final List<ExtraCharge> extraCharges;
  final num extraChargesTotal;
  final num totalAmount;

  CloseOrder({
    required this.status,
    required this.allowedActions,
    required this.orderCode,
    required this.customerName,
    required this.quotedAmount,
    required this.extraCharges,
    required this.extraChargesTotal,
    required this.totalAmount,
  });

  // Server có cho bước này không. Không biết tên hành động thì tin theo status
  bool allows(String keyword) {
    if (allowedActions.isEmpty) {
      return true;
    }
    for (final String action in allowedActions) {
      if (action.toLowerCase().contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  bool get hasUnconfirmed {
    for (final ExtraCharge charge in extraCharges) {
      if (!charge.confirmedWithCustomer) {
        return true;
      }
    }
    return false;
  }

  factory CloseOrder.fromJson(Map<String, dynamic> json) {
    final List<String> actions = <String>[];
    for (final dynamic row in (json['allowedActions'] as List<dynamic>?) ?? <dynamic>[]) {
      actions.add('$row');
    }
    final List<ExtraCharge> charges = <ExtraCharge>[];
    for (final dynamic row in (json['extraCharges'] as List<dynamic>?) ?? <dynamic>[]) {
      charges.add(ExtraCharge.fromJson(row as Map<String, dynamic>));
    }
    // Tên khách có thể nằm trực tiếp hoặc trong object customer
    String customerName = (json['customerName'] as String?) ?? '';
    final dynamic customer = json['customer'];
    if (customerName.isEmpty && customer is Map<String, dynamic>) {
      customerName = (customer['name'] as String?) ?? (customer['fullName'] as String?) ?? '';
    }
    return CloseOrder(
      status: (json['status'] as String?) ?? '',
      allowedActions: actions,
      orderCode: (json['code'] as String?) ?? (json['orderCode'] as String?) ?? '',
      customerName: customerName,
      quotedAmount: (json['quotedAmount'] as num?) ?? 0,
      extraCharges: charges,
      extraChargesTotal: (json['extraChargesTotal'] as num?) ?? 0,
      totalAmount: (json['totalAmount'] as num?) ?? 0,
    );
  }
}

Future<CloseOrder> fetchCloseOrder(String orderId) async {
  return call(
    () {
      return dio.get('/Orders/$orderId');
    },
    (dynamic data) {
      return CloseOrder.fromJson(data as Map<String, dynamic>);
    },
  );
}

// Bước 1: xong việc tại hiện trường. Đang thực hiện → Chờ chốt phát sinh
Future<void> finishOrder(String orderId) async {
  await call(
    () {
      return dio.post('/Orders/$orderId/finish', data: <String, dynamic>{});
    },
    (dynamic data) {
      return null;
    },
  );
}

// Bước 2a: đánh dấu khách đã đồng ý một khoản phát sinh
Future<void> confirmExtraCharge(String orderId, String chargeId) async {
  await call(
    () {
      return dio.post('/Orders/$orderId/extra-charges/$chargeId/confirm');
    },
    (dynamic data) {
      return null;
    },
  );
}

// Bước 2b: chốt đơn, tổng tiền khóa cứng
Future<void> finalizeOrder(String orderId) async {
  await call(
    () {
      return dio.post('/Orders/$orderId/finalize', data: <String, dynamic>{});
    },
    (dynamic data) {
      return null;
    },
  );
}

// Bước 3: ghi nhận đã xuất hóa đơn
Future<void> invoiceOrder(String orderId, String invoiceNumber) async {
  await call(
    () {
      return dio.post('/Orders/$orderId/invoice', data: {'invoiceNumber': invoiceNumber});
    },
    (dynamic data) {
      return null;
    },
  );
}

final closeOrderProvider = FutureProvider.autoDispose.family<CloseOrder, String>((Ref ref, String orderId) {
  return fetchCloseOrder(orderId);
});
