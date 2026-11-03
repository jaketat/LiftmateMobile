// Gọi API đơn hàng, model và các hộp dữ liệu: xem đơn, tạo đơn, đổi bước, thêm phát sinh, AI đọc kiện.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/call.dart';
import '../../core/api/paged_result.dart';
import '../driver/account_api.dart' show newIdempotencyKey;
import 'image_metadata.dart';
import 'order_form.dart';

const int ordersPageSize = 20;

/// Một dòng trong danh sách đơn
class OrderSummary {
  final String publicId;
  final String orderCode;
  final String customerName;
  final String pickupAddress;
  final String deliveryAddress;
  final String? scheduledDate;
  final String? scheduledEndDate;
  final String status;
  final num? quotedAmount;
  final num? finalAmount;

  OrderSummary({
    required this.publicId,
    required this.orderCode,
    required this.customerName,
    required this.pickupAddress,
    required this.deliveryAddress,
    required this.scheduledDate,
    required this.scheduledEndDate,
    required this.status,
    required this.quotedAmount,
    required this.finalAmount,
  });

  factory OrderSummary.fromJson(Map<String, dynamic> data) {
    return OrderSummary(
      publicId: data['publicId'] as String,
      orderCode: data['orderCode'] as String,
      customerName: (data['customerName'] as String?) ?? '',
      pickupAddress: (data['pickupAddress'] as String?) ?? '',
      deliveryAddress: (data['deliveryAddress'] as String?) ?? '',
      scheduledDate: data['scheduledDate'] as String?,
      scheduledEndDate: data['scheduledEndDate'] as String?,
      status: data['status'] as String,
      quotedAmount: data['quotedAmount'] as num?,
      finalAmount: data['finalAmount'] as num?,
    );
  }

  // Đã chốt thì lấy số đã chốt, chưa thì lấy giá báo
  num? get amount => finalAmount ?? quotedAmount;
}

class OrderStop {
  final int sequence;
  // Pickup, Delivery, Via
  final String kind;
  final String address;
  final double? latitude;
  final double? longitude;
  final String? contactName;
  final String? contactPhone;
  final String? note;
  // Crane, ForkliftFromRear. Chỉ điểm trả có
  final String? unloadMethod;

  OrderStop({
    required this.sequence,
    required this.kind,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.contactName,
    required this.contactPhone,
    required this.note,
    this.unloadMethod,
  });

  factory OrderStop.fromJson(Map<String, dynamic> data) {
    return OrderStop(
      sequence: data['sequence'] as int,
      kind: data['kind'] as String,
      address: (data['address'] as String?) ?? '',
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      contactName: data['contactName'] as String?,
      contactPhone: data['contactPhone'] as String?,
      note: data['note'] as String?,
      unloadMethod: data['unloadMethod'] as String?,
    );
  }
}

class OrderWorkDay {
  final String workDate;
  final String startTime;
  final String endTime;
  final bool isOvernight;
  final String? note;

  OrderWorkDay({required this.workDate, required this.startTime, required this.endTime, required this.isOvernight, required this.note});

  factory OrderWorkDay.fromJson(Map<String, dynamic> data) {
    return OrderWorkDay(
      workDate: data['workDate'] as String,
      startTime: data['startTime'] as String,
      endTime: data['endTime'] as String,
      isOvernight: (data['isOvernight'] as bool?) ?? false,
      note: data['note'] as String?,
    );
  }
}

class OrderCargo {
  final String cargoName;
  final int quantity;
  final num weightKg;
  final int lengthMm;
  final int widthMm;
  final int heightMm;
  final bool isFragile;
  final bool doNotStack;
  final String? publicId;
  // Nguyên dữ liệu server: sửa kiện phải gửi lại đủ, kể cả ô app không có (điểm bốc trả, trọng tâm, ngày sẵn sàng)
  final Map<String, dynamic> raw;

  OrderCargo({
    required this.cargoName,
    required this.quantity,
    required this.weightKg,
    required this.lengthMm,
    required this.widthMm,
    required this.heightMm,
    required this.isFragile,
    required this.doNotStack,
    this.publicId,
    this.raw = const <String, dynamic>{},
  });

  factory OrderCargo.fromJson(Map<String, dynamic> data) {
    return OrderCargo(
      cargoName: (data['cargoName'] as String?) ?? '',
      quantity: (data['quantity'] as int?) ?? 1,
      weightKg: (data['weightKg'] as num?) ?? 0,
      lengthMm: (data['lengthMm'] as int?) ?? 0,
      widthMm: (data['widthMm'] as int?) ?? 0,
      heightMm: (data['heightMm'] as int?) ?? 0,
      isFragile: (data['isFragile'] as bool?) ?? false,
      doNotStack: (data['doNotStack'] as bool?) ?? false,
      publicId: data['publicId'] as String?,
      raw: data,
    );
  }
}

class OrderExtraCharge {
  final String publicId;
  final String description;
  final num amount;
  final bool confirmedWithCustomer;
  final String? createdByName;
  final String createdAt;

  OrderExtraCharge({
    required this.publicId,
    required this.description,
    required this.amount,
    required this.confirmedWithCustomer,
    required this.createdByName,
    required this.createdAt,
  });

  factory OrderExtraCharge.fromJson(Map<String, dynamic> data) {
    return OrderExtraCharge(
      publicId: data['publicId'] as String,
      description: (data['description'] as String?) ?? '',
      amount: (data['amount'] as num?) ?? 0,
      confirmedWithCustomer: (data['confirmedWithCustomer'] as bool?) ?? false,
      createdByName: data['createdByName'] as String?,
      createdAt: data['createdAt'] as String,
    );
  }
}

/// Cảnh báo quá khổ, quá tải, điểm nguy hiểm trên tuyến
class OrderWarning {
  final String code;
  final String message;
  final String? legalBasis;

  OrderWarning({required this.code, required this.message, required this.legalBasis});

  factory OrderWarning.fromJson(Map<String, dynamic> data) {
    return OrderWarning(
      code: (data['code'] as String?) ?? '',
      message: (data['message'] as String?) ?? '',
      legalBasis: data['legalBasis'] as String?,
    );
  }

  // Luật cấm chạy kể cả có giấy phép, hoặc va cầu, quá tải cầu: tô đỏ
  bool get isDanger => const <String>{'OVER_DESIGN_PAYLOAD', 'OVER_CLEARANCE', 'HAZARD_LOW_CLEARANCE', 'HAZARD_WEIGHT_LIMIT'}.contains(code);
}

List<T> _list<T>(Object? value, T Function(Map<String, dynamic> json) parse) {
  return <T>[for (final dynamic row in (value as List<dynamic>?) ?? <dynamic>[]) parse(row as Map<String, dynamic>)];
}

String? _vehicleLabel(Object? data) {
  if (data is! Map<String, dynamic>) return null;
  return (data['plateNumber'] as String?) ?? (data['vehicleType'] as String?);
}

class OrderDetail {
  final String publicId;
  final String orderCode;
  final String? customerId;
  final String customerName;
  final String customerPhone;
  final String status;
  final List<String> allowedActions;
  final List<OrderStop> stops;
  final List<OrderWorkDay> workDays;
  final List<OrderCargo> cargos;
  final int totalCargosCount;
  final num totalWeightKg;
  final num totalVolumeM3;
  final num? quotedAmount;
  final num extraChargesTotal;
  final num totalAmount;
  final num? finalAmount;
  final List<OrderExtraCharge> extraCharges;
  final String? invoiceNumber;
  final num totalDistanceKm;
  final num estimatedFuelCost;
  final num tollCost;
  final String? routePolyline;
  final String? routeWarning;
  final String? fuelWarning;
  final bool tollClassAssumed;
  final String? cancelReason;
  final String? notes;
  final String createdAt;
  final List<OrderWarning> oversizeWarnings;
  final String? oversizeAcknowledgedByName;
  // Chỉ có khi vừa tạo đơn: số điện thoại khách mới trùng khách đã có (BR-ORD-030)
  final bool customerMatchedByPhone;
  final String? customerNotice;
  final String operatingProfile;
  // Xe dùng để ước tính tiền dầu: sửa đơn phải gửi lại, bỏ trống là bị xóa
  final String? estimationVehicleId;
  final String? estimationTractorId;
  final String? estimationVehicleLabel;
  final String? estimationTractorLabel;

  OrderDetail({
    required this.publicId,
    required this.orderCode,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.status,
    required this.allowedActions,
    required this.stops,
    required this.workDays,
    required this.cargos,
    required this.totalCargosCount,
    required this.totalWeightKg,
    required this.totalVolumeM3,
    required this.quotedAmount,
    required this.extraChargesTotal,
    required this.totalAmount,
    required this.finalAmount,
    required this.extraCharges,
    required this.invoiceNumber,
    required this.totalDistanceKm,
    required this.estimatedFuelCost,
    required this.tollCost,
    required this.routePolyline,
    required this.routeWarning,
    required this.fuelWarning,
    required this.tollClassAssumed,
    required this.cancelReason,
    required this.notes,
    required this.createdAt,
    required this.oversizeWarnings,
    required this.oversizeAcknowledgedByName,
    this.customerMatchedByPhone = false,
    this.customerNotice,
    this.operatingProfile = 'Balanced',
    this.estimationVehicleId,
    this.estimationTractorId,
    this.estimationVehicleLabel,
    this.estimationTractorLabel,
  });

  factory OrderDetail.fromJson(Map<String, dynamic> data) {
    final Map<String, dynamic> customer = (data['customer'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return OrderDetail(
      publicId: data['publicId'] as String,
      orderCode: data['orderCode'] as String,
      customerId: customer['publicId'] as String?,
      customerName: (customer['customerName'] as String?) ?? '',
      customerPhone: (customer['phone'] as String?) ?? '',
      status: data['status'] as String,
      allowedActions: <String>[for (final dynamic action in (data['allowedActions'] as List<dynamic>?) ?? <dynamic>[]) action as String],
      stops: _list(data['stops'], OrderStop.fromJson),
      workDays: _list(data['workDays'], OrderWorkDay.fromJson),
      cargos: _list(data['cargos'], OrderCargo.fromJson),
      totalCargosCount: (data['totalCargosCount'] as int?) ?? 0,
      totalWeightKg: (data['totalWeightKg'] as num?) ?? 0,
      totalVolumeM3: (data['totalVolumeM3'] as num?) ?? 0,
      quotedAmount: data['quotedAmount'] as num?,
      extraChargesTotal: (data['extraChargesTotal'] as num?) ?? 0,
      totalAmount: (data['totalAmount'] as num?) ?? 0,
      finalAmount: data['finalAmount'] as num?,
      extraCharges: _list(data['extraCharges'], OrderExtraCharge.fromJson),
      invoiceNumber: data['invoiceNumber'] as String?,
      totalDistanceKm: (data['totalDistanceKm'] as num?) ?? 0,
      estimatedFuelCost: (data['estimatedFuelCost'] as num?) ?? 0,
      tollCost: (data['tollCost'] as num?) ?? 0,
      routePolyline: data['routePolyline'] as String?,
      routeWarning: data['routeWarning'] as String?,
      fuelWarning: data['fuelWarning'] as String?,
      tollClassAssumed: (data['tollClassAssumed'] as bool?) ?? false,
      cancelReason: data['cancelReason'] as String?,
      notes: data['notes'] as String?,
      createdAt: data['createdAt'] as String,
      oversizeWarnings: _list(data['oversizeWarnings'], OrderWarning.fromJson),
      oversizeAcknowledgedByName: data['oversizeAcknowledgedByName'] as String?,
      customerMatchedByPhone: (data['customerMatchedByPhone'] as bool?) ?? false,
      customerNotice: data['customerNotice'] as String?,
      operatingProfile: (data['operatingProfile'] as String?) ?? 'Balanced',
      estimationVehicleId: (data['estimationVehicle'] as Map<String, dynamic>?)?['publicId'] as String?,
      estimationTractorId: (data['estimationTractor'] as Map<String, dynamic>?)?['publicId'] as String?,
      estimationVehicleLabel: _vehicleLabel(data['estimationVehicle']),
      estimationTractorLabel: _vehicleLabel(data['estimationTractor']),
    );
  }

  bool get hasCoordinates => stops.any((OrderStop stop) => stop.latitude != null && stop.longitude != null);

  // Phát sinh chỉ thêm, sửa được khi đơn Đang thực hiện hoặc Chờ chốt phát sinh (BR slice-03 mục 2.7)
  bool get extrasEditable => status == 'InProgress' || status == 'AwaitingFinalization';
}

class OrderHistoryItem {
  final String? fromStatus;
  final String toStatus;
  final String action;
  final String? reason;
  final String? note;
  final String? actorName;
  final String occurredAt;

  OrderHistoryItem({
    required this.fromStatus,
    required this.toStatus,
    required this.action,
    required this.reason,
    required this.note,
    required this.actorName,
    required this.occurredAt,
  });

  factory OrderHistoryItem.fromJson(Map<String, dynamic> data) {
    return OrderHistoryItem(
      fromStatus: data['fromStatus'] as String?,
      toStatus: data['toStatus'] as String,
      action: (data['action'] as String?) ?? '',
      reason: data['reason'] as String?,
      note: data['note'] as String?,
      actorName: data['actorName'] as String?,
      occurredAt: data['occurredAt'] as String,
    );
  }
}

Future<PagedResult<OrderSummary>> fetchOrders(int pageNumber, {String search = '', String? status}) {
  return call(
    () => dio.get('/orders', queryParameters: <String, dynamic>{
      'pageNumber': pageNumber,
      'pageSize': ordersPageSize,
      if (search.isNotEmpty) 'searchTerm': search,
      if (status != null) 'status': status,
    }),
    (dynamic data) => PagedResult<OrderSummary>.fromJson(data as Map<String, dynamic>, OrderSummary.fromJson),
  );
}

Future<OrderDetail> fetchOrder(String orderId) {
  return call(() => dio.get('/orders/$orderId'), (dynamic data) => OrderDetail.fromJson(data as Map<String, dynamic>));
}

Future<List<OrderHistoryItem>> fetchOrderHistory(String orderId) {
  return call(() => dio.get('/orders/$orderId/history'), (dynamic data) => _list(data, OrderHistoryItem.fromJson));
}

/// Điểm nguy hiểm trên tuyến: chốt lịch phải xác nhận cùng cảnh báo quá khổ
Future<List<OrderWarning>> fetchOrderHazardWarnings(String orderId) {
  return call(
    () => dio.get('/orders/$orderId/route-hazards'),
    (dynamic data) => _list((data as Map<String, dynamic>)['warnings'], OrderWarning.fromJson),
  );
}

/// Số biên bản giao hàng trong hồ sơ đơn: chưa có thì chỉ nhắc, không chặn
Future<int> fetchOrderPodCount(String orderId) {
  return call(
    () => dio.get('/orders/$orderId/documents', queryParameters: <String, dynamic>{'documentType': 'POD'}),
    (dynamic data) => ((data as Map<String, dynamic>)['totalCount'] as num?)?.toInt() ?? 0,
  );
}

/// Đổi bước đơn. [path] là đuôi đường dẫn: send-quote, confirm, ... Trả về mã đơn.
Future<void> runOrderAction(String orderId, String path, {String? reason, String? note, String? invoiceNumber, bool acknowledgeOversize = false}) {
  return call(
    () => dio.post('/orders/$orderId/$path', data: <String, dynamic>{
      if (reason != null) 'reason': reason,
      if (note != null) 'note': note,
      if (invoiceNumber != null) 'invoiceNumber': invoiceNumber,
      if (acknowledgeOversize) 'acknowledgeOversize': true,
    }),
    (dynamic data) {},
  );
}

Future<OrderDetail> addExtraCharge(String orderId, {required String description, required int amount, required bool confirmed, String? idempotencyKey}) {
  return call(
    () => dio.post(
      '/orders/$orderId/extra-charges',
      data: <String, dynamic>{'description': description, 'amount': amount, 'confirmedWithCustomer': confirmed},
      options: Options(headers: <String, dynamic>{'Idempotency-Key': idempotencyKey ?? newIdempotencyKey()}),
    ),
    (dynamic data) => OrderDetail.fromJson(data as Map<String, dynamic>),
  );
}

Future<OrderDetail> confirmExtraCharge(String orderId, String chargeId) {
  return call(() => dio.post('/orders/$orderId/extra-charges/$chargeId/confirm'), (dynamic data) => OrderDetail.fromJson(data as Map<String, dynamic>));
}

Future<OrderDetail> removeExtraCharge(String orderId, String chargeId) {
  return call(() => dio.delete('/orders/$orderId/extra-charges/$chargeId'), (dynamic data) => OrderDetail.fromJson(data as Map<String, dynamic>));
}

Future<OrderDetail> createOrder(Map<String, dynamic> body, {required String idempotencyKey}) {
  return call(
    () => dio.post('/orders', data: body, options: Options(headers: <String, dynamic>{'Idempotency-Key': idempotencyKey})),
    (dynamic data) => OrderDetail.fromJson(data as Map<String, dynamic>),
  );
}

Future<void> updateOrder(String orderId, Map<String, dynamic> body) {
  return call(() => dio.put('/orders/$orderId', data: body), (dynamic data) => null);
}

/// Đơn đã khóa: gửi đề nghị sửa cho giám đốc duyệt (BR-ORD-079). kind: OrderInfo hoặc WorkDays
Future<void> createOrderEditRequest(String orderId, Map<String, dynamic> body) {
  return call(() => dio.post('/orders/$orderId/edit-requests', data: body), (dynamic data) => null);
}

Future<void> replaceOrderWorkDays(String orderId, List<Map<String, dynamic>> workDays) {
  return call(() => dio.put('/orders/$orderId/work-days', data: <String, dynamic>{'workDays': workDays}), (dynamic data) => null);
}

Future<void> addOrderCargos(String orderId, List<Map<String, dynamic>> cargos, {required String idempotencyKey}) {
  return call(
    () => dio.post('/orders/$orderId/cargos', data: <String, dynamic>{'cargos': cargos}, options: Options(headers: <String, dynamic>{'Idempotency-Key': idempotencyKey})),
    (dynamic data) => null,
  );
}

Future<void> updateOrderCargo(String orderId, String cargoId, Map<String, dynamic> body) {
  return call(() => dio.put('/orders/$orderId/cargos/$cargoId', data: body), (dynamic data) => null);
}

Future<void> deleteOrderCargo(String orderId, String cargoId) {
  return call(() => dio.delete('/orders/$orderId/cargos/$cargoId'), (dynamic data) => null);
}

/// Gợi ý địa chỉ Vietmap: chưa có tọa độ, chọn rồi mới gọi fetchPlace
class AddressSuggestion {
  final String refId;
  final String display;
  final String? displayOld;
  final String? name;

  AddressSuggestion({required this.refId, required this.display, required this.displayOld, required this.name});

  factory AddressSuggestion.fromJson(Map<String, dynamic> data) {
    return AddressSuggestion(
      refId: data['refId'] as String,
      display: (data['display'] as String?) ?? '',
      displayOld: data['displayOld'] as String?,
      name: data['name'] as String?,
    );
  }
}

class PlaceDetail {
  final String display;
  final double latitude;
  final double longitude;

  PlaceDetail({required this.display, required this.latitude, required this.longitude});
}

Future<List<AddressSuggestion>> searchAddresses(String query) {
  return call(
    () => dio.get('/orders/search-addresses', queryParameters: <String, dynamic>{'query': query}),
    (dynamic data) => _list(data, AddressSuggestion.fromJson),
  );
}

Future<PlaceDetail> fetchPlace(String refId) {
  return call(
    () => dio.get('/orders/places', queryParameters: <String, dynamic>{'refId': refId}),
    (dynamic data) {
      final Map<String, dynamic> json = data as Map<String, dynamic>;
      return PlaceDetail(
        display: (json['display'] as String?) ?? '',
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
      );
    },
  );
}

class RouteEstimate {
  final num distanceKm;
  final num tollCost;
  final String? warning;
  final bool tollClassAssumed;
  // Đường xe tải đã tính (polyline Google), để vẽ tuyến
  final String? polyline;
  final num? durationMinutes;
  final int? tollVehicleClass;
  final List<String> expressways;
  // Tiền dầu: lúc tạo đơn web và app không hiện (mới biết 1 xe, một chiều nên thấp hơn thật nhiều lần); sửa đơn thì hiện
  final num? estimatedFuelCost;
  final num? fuelPricePerLiter;
  final String? fuelPriceEffectiveDate;
  final num? fuelConsumptionPer100Km;
  final String? fuelWarning;

  RouteEstimate({
    required this.distanceKm,
    required this.tollCost,
    required this.warning,
    required this.tollClassAssumed,
    this.polyline,
    this.durationMinutes,
    this.tollVehicleClass,
    this.expressways = const <String>[],
    this.estimatedFuelCost,
    this.fuelPricePerLiter,
    this.fuelPriceEffectiveDate,
    this.fuelConsumptionPer100Km,
    this.fuelWarning,
  });

  factory RouteEstimate.fromJson(Map<String, dynamic> json) {
    return RouteEstimate(
      distanceKm: (json['distanceKm'] as num?) ?? 0,
      tollCost: (json['tollCost'] as num?) ?? 0,
      warning: json['warning'] as String?,
      tollClassAssumed: (json['tollClassAssumed'] as bool?) ?? true,
      polyline: json['polyline'] as String?,
      durationMinutes: json['durationMinutes'] as num?,
      tollVehicleClass: (json['tollVehicleClass'] as num?)?.toInt(),
      expressways: <String>[for (final dynamic name in (json['routeExpressways'] as List<dynamic>?) ?? <dynamic>[]) '$name'],
      estimatedFuelCost: json['estimatedFuelCost'] as num?,
      fuelPricePerLiter: json['fuelPricePerLiter'] as num?,
      fuelPriceEffectiveDate: json['fuelPriceEffectiveDate'] as String?,
      fuelConsumptionPer100Km: json['fuelConsumptionPer100Km'] as num?,
      fuelWarning: json['fuelWarning'] as String?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'distanceKm': distanceKm,
        'tollCost': tollCost,
        'warning': warning,
        'tollClassAssumed': tollClassAssumed,
        'polyline': polyline,
        'durationMinutes': durationMinutes,
        'tollVehicleClass': tollVehicleClass,
        'routeExpressways': expressways,
        'estimatedFuelCost': estimatedFuelCost,
        'fuelPricePerLiter': fuelPricePerLiter,
        'fuelPriceEffectiveDate': fuelPriceEffectiveDate,
        'fuelConsumptionPer100Km': fuelConsumptionPer100Km,
        'fuelWarning': fuelWarning,
      };
}

Future<RouteEstimate> estimateOrderRoute(Map<String, dynamic> request) {
  return call(
    () => dio.post('/orders/estimate-route', data: request),
    (dynamic data) => RouteEstimate.fromJson(data as Map<String, dynamic>),
  );
}

class AiCargoResult {
  final List<CargoDraft> cargos;
  final List<String> warnings;
  final String? dataNotice;
  final int? usedThisMonth;
  final int? monthlyLimit;

  AiCargoResult({required this.cargos, required this.warnings, this.dataNotice, this.usedThisMonth, this.monthlyLimit});
}

class AiImageText {
  final String text;
  final String? dataNotice;
  final int? usedThisMonth;
  final int? monthlyLimit;

  AiImageText({required this.text, this.dataNotice, this.usedThisMonth, this.monthlyLimit});
}

// Đọc bằng AI lâu hơn các lệnh thường
const Duration _aiTimeout = Duration(seconds: 120);

Future<AiCargoResult> parseCargoText(String rawText, {CancelToken? cancelToken}) {
  return call(
    () => dio.post('/orders/ai-parse-cargos', data: <String, dynamic>{'rawText': rawText}, options: Options(receiveTimeout: _aiTimeout), cancelToken: cancelToken),
    (dynamic data) {
      final Map<String, dynamic> json = data as Map<String, dynamic>;
      return AiCargoResult(
        cargos: _list(json['cargos'], CargoDraft.fromAi),
        warnings: <String>[for (final dynamic warning in (json['warnings'] as List<dynamic>?) ?? <dynamic>[]) warning as String],
        dataNotice: json['dataNotice'] as String?,
        usedThisMonth: (json['usedThisMonth'] as num?)?.toInt(),
        monthlyLimit: (json['monthlyLimit'] as num?)?.toInt(),
      );
    },
  );
}

/// Chép chữ trong ảnh (bảng kê, chụp màn hình tin nhắn) để người dùng so lại trước khi đọc kiện
Future<AiImageText> readCargoImage(String filePath, {CancelToken? cancelToken}) async {
  // Ảnh đi sang dịch vụ ngoài: xóa vị trí và thông tin máy chụp trước. Không xóa được thì ném FormatException, không gửi.
  final CleanImage image = await compute(stripImageMetadata, await File(filePath).readAsBytes());
  final FormData form = FormData.fromMap(<String, dynamic>{
    'file': MultipartFile.fromBytes(image.bytes, filename: image.fileName, contentType: DioMediaType('image', image.subtype)),
  });
  return call(
    () => dio.post('/orders/ai-read-image', data: form, options: Options(receiveTimeout: _aiTimeout), cancelToken: cancelToken),
    (dynamic data) {
      final Map<String, dynamic> json = data as Map<String, dynamic>;
      return AiImageText(
        text: (json['text'] as String?) ?? '',
        dataNotice: json['dataNotice'] as String?,
        usedThisMonth: (json['usedThisMonth'] as num?)?.toInt(),
        monthlyLimit: (json['monthlyLimit'] as num?)?.toInt(),
      );
    },
  );
}

final orderDetailProvider = FutureProvider.autoDispose.family<OrderDetail, String>((Ref ref, String orderId) => fetchOrder(orderId));

final orderHistoryProvider = FutureProvider.autoDispose.family<List<OrderHistoryItem>, String>((Ref ref, String orderId) => fetchOrderHistory(orderId));
