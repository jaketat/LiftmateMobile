// Gọi API kế hoạch chia chuyến (doc mục 3.2, 3.3, 3.4, 3.5).
import '../../core/api/api_client.dart';
import '../../core/api/call.dart';

// Hai id xác định một kế hoạch: đơn và kế hoạch
typedef PlanKey = ({String orderId, String planId});

// Xe trong kế hoạch (xe tải, moóc hoặc đầu kéo)
class PlanVehicle {
  final String id;
  final String plateNumber;
  // Truck, Trailer, TractorHead...
  final String baseType;
  final num payloadKg;

  PlanVehicle({required this.id, required this.plateNumber, required this.baseType, required this.payloadKg});

  factory PlanVehicle.fromJson(Map<String, dynamic> json) {
    return PlanVehicle(
      id: (json['id'] as String?) ?? '',
      plateNumber: (json['plateNumber'] as String?) ?? '',
      baseType: (json['baseType'] as String?) ?? '',
      payloadKg: (json['payloadKg'] as num?) ?? 0,
    );
  }
}

// Một kiện trong chuyến
class PlanItem {
  final String cargoName;
  final int quantity;

  PlanItem({required this.cargoName, required this.quantity});

  factory PlanItem.fromJson(Map<String, dynamic> json) {
    return PlanItem(
      cargoName: (json['cargoName'] as String?) ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
    );
  }
}

// Một chuyến trong kế hoạch. id là "chuyến kế hoạch" (plannedTripId), khác id chuyến chạy
class PlanTrip {
  final String id;
  final int sequence;
  final int deliveryWave;
  // Planned, Locked, Executed
  final String status;
  final PlanVehicle? carrier;
  // Có khi xe chở là moóc
  final PlanVehicle? tractor;
  // Pass, Fail, Unchecked
  final String verdict;
  final bool nearLimit;
  final num cargoKg;
  final List<PlanItem> items;
  // Cảnh báo, gợi ý sửa: chữ tiếng Việt, hiện thẳng
  final List<String> warnings;
  final List<String> fixHints;

  PlanTrip({
    required this.id,
    required this.sequence,
    required this.deliveryWave,
    required this.status,
    required this.carrier,
    required this.tractor,
    required this.verdict,
    required this.nearLimit,
    required this.cargoKg,
    required this.items,
    required this.warnings,
    required this.fixHints,
  });

  int get itemCount {
    int total = 0;
    for (final PlanItem item in items) {
      total += item.quantity;
    }
    return total;
  }

  factory PlanTrip.fromJson(Map<String, dynamic> json) {
    final List<PlanItem> items = <PlanItem>[];
    for (final dynamic row in (json['items'] as List<dynamic>?) ?? <dynamic>[]) {
      items.add(PlanItem.fromJson(row as Map<String, dynamic>));
    }

    // layout có thể thiếu; warnings, fixHints là danh sách chữ (hoặc object có message)
    final Map<String, dynamic> layout = (json['layout'] as Map<String, dynamic>?) ?? <String, dynamic>{};

    return PlanTrip(
      id: json['id'] as String,
      sequence: (json['sequence'] as num?)?.toInt() ?? 0,
      deliveryWave: (json['deliveryWave'] as num?)?.toInt() ?? 1,
      status: (json['status'] as String?) ?? 'Planned',
      carrier: json['carrier'] == null ? null : PlanVehicle.fromJson(json['carrier'] as Map<String, dynamic>),
      tractor: json['tractor'] == null ? null : PlanVehicle.fromJson(json['tractor'] as Map<String, dynamic>),
      verdict: (json['verdict'] as String?) ?? 'Unchecked',
      nearLimit: (json['nearLimit'] as bool?) ?? false,
      cargoKg: (json['cargoKg'] as num?) ?? 0,
      items: items,
      warnings: _textList(layout['warnings']),
      fixHints: _textList(layout['fixHints']),
    );
  }
}

// Đổi danh sách bất kỳ (chữ hoặc object có message) thành danh sách chữ
List<String> _textList(dynamic value) {
  final List<String> texts = <String>[];
  for (final dynamic row in (value as List<dynamic>?) ?? <dynamic>[]) {
    if (row is String) {
      texts.add(row);
    } else if (row is Map<String, dynamic> && row['message'] is String) {
      texts.add(row['message'] as String);
    }
  }
  return texts;
}

// Kiện không xếp được
class UnplannedCargo {
  final int quantity;
  // Lý do, câu tiếng Việt server viết sẵn
  final String message;

  UnplannedCargo({required this.quantity, required this.message});

  factory UnplannedCargo.fromJson(Map<String, dynamic> json) {
    return UnplannedCargo(
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      message: (json['message'] as String?) ?? '',
    );
  }
}

// Kiện chưa sẵn sàng (ngày sẵn sàng sau ngày kế hoạch)
class PendingCargo {
  final int quantity;
  final String? readyDate;

  PendingCargo({required this.quantity, required this.readyDate});

  factory PendingCargo.fromJson(Map<String, dynamic> json) {
    return PendingCargo(
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      readyDate: json['readyDate'] as String?,
    );
  }
}

class ShipmentPlan {
  // planId
  final String id;
  final int version;
  // Draft, Approved, Superseded
  final String status;
  // true: kiện, điểm dừng hoặc xe đã đổi sau khi sinh, phải lên lại kế hoạch
  final bool isStale;
  final int lowerBoundTrips;
  final List<PlanTrip> trips;
  final List<UnplannedCargo> unplanned;
  final List<PendingCargo> pending;

  ShipmentPlan({
    required this.id,
    required this.version,
    required this.status,
    required this.isStale,
    required this.lowerBoundTrips,
    required this.trips,
    required this.unplanned,
    required this.pending,
  });

  bool get isDraft => status == 'Draft';

  // Các chuyến Không đạt: còn chuyến nào thì chưa duyệt được
  List<PlanTrip> get failedTrips {
    final List<PlanTrip> failed = <PlanTrip>[];
    for (final PlanTrip trip in trips) {
      if (trip.verdict == 'Fail') {
        failed.add(trip);
      }
    }
    return failed;
  }

  num get totalKg {
    num total = 0;
    for (final PlanTrip trip in trips) {
      total += trip.cargoKg;
    }
    return total;
  }

  int get totalItems {
    int total = 0;
    for (final PlanTrip trip in trips) {
      total += trip.itemCount;
    }
    return total;
  }

  factory ShipmentPlan.fromJson(Map<String, dynamic> json) {
    final List<PlanTrip> trips = <PlanTrip>[];
    for (final dynamic row in (json['trips'] as List<dynamic>?) ?? <dynamic>[]) {
      trips.add(PlanTrip.fromJson(row as Map<String, dynamic>));
    }
    final List<UnplannedCargo> unplanned = <UnplannedCargo>[];
    for (final dynamic row in (json['unplanned'] as List<dynamic>?) ?? <dynamic>[]) {
      unplanned.add(UnplannedCargo.fromJson(row as Map<String, dynamic>));
    }
    final List<PendingCargo> pending = <PendingCargo>[];
    for (final dynamic row in (json['pending'] as List<dynamic>?) ?? <dynamic>[]) {
      pending.add(PendingCargo.fromJson(row as Map<String, dynamic>));
    }
    return ShipmentPlan(
      id: json['id'] as String,
      version: (json['version'] as num?)?.toInt() ?? 1,
      status: (json['status'] as String?) ?? 'Draft',
      isStale: (json['isStale'] as bool?) ?? false,
      lowerBoundTrips: (json['lowerBoundTrips'] as num?)?.toInt() ?? 0,
      trips: trips,
      unplanned: unplanned,
      pending: pending,
    );
  }
}

// Kế hoạch hiện hành (đã duyệt; chưa duyệt thì bản mới nhất). Đơn chưa chia thì 404 PLAN_NOT_FOUND
Future<ShipmentPlan> fetchCurrentPlan(String orderId) async {
  return call(
    () {
      return dio.get('/orders/$orderId/shipment-plans/current');
    },
    (dynamic data) {
      return ShipmentPlan.fromJson(data as Map<String, dynamic>);
    },
  );
}

// Chia chuyến (và lên lại kế hoạch): mỗi lần gọi tạo một bản Nháp mới. Có thể mất vài giây
Future<ShipmentPlan> generatePlan(String orderId) async {
  return call(
    () {
      // Body rỗng: dùng mọi xe đủ điều kiện, ngày hôm nay
      return dio.post('/orders/$orderId/shipment-plans', data: <String, dynamic>{});
    },
    (dynamic data) {
      return ShipmentPlan.fromJson(data as Map<String, dynamic>);
    },
  );
}

Future<void> approvePlan(PlanKey key) async {
  await call(
    () {
      return dio.post('/orders/${key.orderId}/shipment-plans/${key.planId}/approve');
    },
    (dynamic data) {
      return null;
    },
  );
}

// Tổng tiền dầu khứ hồi của cả kế hoạch, để hiện ở khung tổng. Lỗi thì trả null, không làm hỏng cả màn
Future<num?> fetchCostTotal(PlanKey key) async {
  try {
    return await call(
      () {
        return dio.get('/orders/${key.orderId}/shipment-plans/${key.planId}/cost-estimate');
      },
      (dynamic data) {
        return (data as Map<String, dynamic>)['total'] as num?;
      },
    );
  } on ApiException {
    return null;
  }
}

// Tiền dầu và phí BOT ước tính của một chuyến (chiều về tính bằng chiều đi)
class TripCost {
  final int sequence;
  // Vd "Chuyến 1 · 51C-90001"
  final String vehicleLabel;
  final num distanceKm;
  // true: quãng đường ước lượng, hiện thêm chữ "khoảng"
  final bool distanceApproximate;
  final num fuelRoundTrip;
  final num tollRoundTrip;
  final num roundTripTotal;
  // true: xe chưa khai mức tiêu hao, đang dùng mức mặc định
  final bool usedDefaultConsumption;
  final String note;

  TripCost({
    required this.sequence,
    required this.vehicleLabel,
    required this.distanceKm,
    required this.distanceApproximate,
    required this.fuelRoundTrip,
    required this.tollRoundTrip,
    required this.roundTripTotal,
    required this.usedDefaultConsumption,
    required this.note,
  });

  factory TripCost.fromJson(Map<String, dynamic> json) {
    return TripCost(
      sequence: (json['sequence'] as num?)?.toInt() ?? 0,
      vehicleLabel: (json['vehicleLabel'] as String?) ?? '',
      distanceKm: (json['distanceKm'] as num?) ?? 0,
      distanceApproximate: (json['distanceApproximate'] as bool?) ?? false,
      fuelRoundTrip: (json['fuelRoundTrip'] as num?) ?? 0,
      tollRoundTrip: (json['tollRoundTrip'] as num?) ?? 0,
      roundTripTotal: (json['roundTripTotal'] as num?) ?? 0,
      usedDefaultConsumption: (json['usedDefaultConsumption'] as bool?) ?? false,
      note: (json['note'] as String?) ?? '',
    );
  }
}

class CostEstimate {
  final List<TripCost> trips;
  final num fuelTotal;
  final num tollTotal;
  final num total;
  final num pricePerLiter;
  // Ngày áp dụng giá dầu, dạng "2026-10-15"
  final String? priceEffectiveDate;
  // true: giá dầu có thể đã cũ
  final bool priceStale;
  // true: có chuyến thiếu phí BOT (hết lượt bản đồ)
  final bool incomplete;

  CostEstimate({
    required this.trips,
    required this.fuelTotal,
    required this.tollTotal,
    required this.total,
    required this.pricePerLiter,
    required this.priceEffectiveDate,
    required this.priceStale,
    required this.incomplete,
  });

  factory CostEstimate.fromJson(Map<String, dynamic> json) {
    final List<TripCost> trips = <TripCost>[];
    for (final dynamic row in (json['trips'] as List<dynamic>?) ?? <dynamic>[]) {
      trips.add(TripCost.fromJson(row as Map<String, dynamic>));
    }
    return CostEstimate(
      trips: trips,
      fuelTotal: (json['fuelTotal'] as num?) ?? 0,
      tollTotal: (json['tollTotal'] as num?) ?? 0,
      total: (json['total'] as num?) ?? 0,
      pricePerLiter: (json['pricePerLiter'] as num?) ?? 0,
      priceEffectiveDate: json['priceEffectiveDate'] as String?,
      priceStale: (json['priceStale'] as bool?) ?? false,
      incomplete: (json['incomplete'] as bool?) ?? false,
    );
  }
}

Future<CostEstimate> fetchCostEstimate(PlanKey key) async {
  return call(
    () {
      return dio.get('/orders/${key.orderId}/shipment-plans/${key.planId}/cost-estimate');
    },
    (dynamic data) {
      return CostEstimate.fromJson(data as Map<String, dynamic>);
    },
  );
}
