// Gọi API khách hàng (doc mục 3.6) + đơn gần đây của khách, model và các hộp dữ liệu.
// Riverpod: FutureProvider, Ref
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/call.dart';
import '../../core/api/paged_result.dart';

class Customer {
  final String publicId;
  // Server tự sinh: KH-0012 (khách thường) hoặc VL-0004 (khách vãng lai)
  final String customerCode;
  final String customerName;
  final String? contactPerson;
  final String phone;
  final String? email;
  final String? address;
  final String? taxCode;

  Customer({
    required this.publicId,
    required this.customerCode,
    required this.customerName,
    required this.contactPerson,
    required this.phone,
    required this.email,
    required this.address,
    required this.taxCode,
  });

  // API không đánh dấu khách tạo nhanh: chỉ nhận ra khách vãng lai qua mã VL-
  bool get isWalkIn {
    return customerCode.startsWith('VL-');
  }

  factory Customer.fromJson(Map<String, dynamic> data) {
    return Customer(
      publicId: data['publicId'] as String,
      customerCode: data['customerCode'] as String,
      customerName: data['customerName'] as String,
      contactPerson: data['contactPerson'] as String?,
      phone: (data['phone'] as String?) ?? '',
      email: data['email'] as String?,
      address: data['address'] as String?,
      taxCode: data['taxCode'] as String?,
    );
  }
}

class CustomerDetail {
  final Customer customer;
  final String? note;
  final int totalOrdersCount;
  final int activeOrdersCount;
  // Null thì ẩn ô "Đã chi"
  final num? totalSpentAmount;

  CustomerDetail({
    required this.customer,
    required this.note,
    required this.totalOrdersCount,
    required this.activeOrdersCount,
    required this.totalSpentAmount,
  });

  factory CustomerDetail.fromJson(Map<String, dynamic> data) {
    return CustomerDetail(
      customer: Customer.fromJson(data),
      note: data['note'] as String?,
      totalOrdersCount: (data['totalOrdersCount'] as num?)?.toInt() ?? 0,
      activeOrdersCount: (data['activeOrdersCount'] as num?)?.toInt() ?? 0,
      totalSpentAmount: data['totalSpentAmount'] as num?,
    );
  }
}

// Một đơn trong "Đơn gần đây"
class RecentOrder {
  final String publicId;
  final String orderCode;
  final String status;
  final String? scheduledDate;
  final String createdAt;

  RecentOrder({
    required this.publicId,
    required this.orderCode,
    required this.status,
    required this.scheduledDate,
    required this.createdAt,
  });

  factory RecentOrder.fromJson(Map<String, dynamic> data) {
    return RecentOrder(
      publicId: data['publicId'] as String,
      orderCode: data['orderCode'] as String,
      status: data['status'] as String,
      scheduledDate: data['scheduledDate'] as String?,
      createdAt: data['createdAt'] as String,
    );
  }
}

// C1: một trang khách. searchTerm tìm theo tên, mã, SĐT, mã số thuế, người liên hệ.
Future<PagedResult<Customer>> fetchCustomers(int pageNumber, String search) async {
  final Map<String, dynamic> query = <String, dynamic>{'pageNumber': pageNumber, 'pageSize': 20};
  if (search.isNotEmpty) {
    query['searchTerm'] = search;
  }
  return call(
    () {
      return dio.get('/Customers', queryParameters: query);
    },
    (dynamic data) {
      return PagedResult<Customer>.fromJson(data as Map<String, dynamic>, Customer.fromJson);
    },
  );
}

// C2
Future<CustomerDetail> fetchCustomer(String customerId) async {
  return call(
    () {
      return dio.get('/Customers/$customerId');
    },
    (dynamic data) {
      return CustomerDetail.fromJson(data as Map<String, dynamic>);
    },
  );
}

// C2: 5 đơn gần đây của khách
Future<List<RecentOrder>> fetchRecentOrders(String customerId) async {
  return call(
    () {
      return dio.get('/Orders', queryParameters: {'customerPublicId': customerId, 'pageNumber': 1, 'pageSize': 5});
    },
    (dynamic data) {
      return PagedResult<RecentOrder>.fromJson(data as Map<String, dynamic>, RecentOrder.fromJson).items;
    },
  );
}

// C3: thêm khách. Không gửi customerCode: server tự sinh. Trả về khách vừa tạo (mã 201).
Future<CustomerDetail> createCustomer(Map<String, dynamic> body) async {
  return call(
    () {
      return dio.post('/Customers', data: body);
    },
    (dynamic data) {
      return CustomerDetail.fromJson(data as Map<String, dynamic>);
    },
  );
}

final customerProvider = FutureProvider.autoDispose.family<CustomerDetail, String>((Ref ref, String customerId) {
  return fetchCustomer(customerId);
});

final customerOrdersProvider = FutureProvider.autoDispose.family<List<RecentOrder>, String>((Ref ref, String customerId) {
  return fetchRecentOrders(customerId);
});
