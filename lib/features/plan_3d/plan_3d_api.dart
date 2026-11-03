// Gọi API cho sơ đồ 2D (doc mục 3.8) và dữ liệu 3D (doc mục 3.7, 3.9).
import '../../core/api/api_client.dart';
import '../../core/api/call.dart';
import '../../core/i18n.dart';

// Ba id xác định một chuyến. Record (Dart): gói nhiều giá trị, so sánh theo giá trị nên dùng làm khóa hộp family được
typedef TripKey = ({String orderId, String planId, String tripId});

// Sơ đồ 2D server vẽ sẵn
class TripBlueprint {
  // Chuỗi SVG mặt bằng (nhìn từ trên) và mặt đứng (nhìn ngang)
  final String topViewSvg;
  final String sideViewSvg;
  final String plateNumber;
  final List<String> notes;
  // true: hiện băng vàng "NHÁP" kèm lý do
  final bool isDraft;
  final String draftReason;
  // Tỷ lệ, vd "1:50"
  final String scale;

  TripBlueprint({
    required this.topViewSvg,
    required this.sideViewSvg,
    required this.plateNumber,
    required this.notes,
    required this.isDraft,
    required this.draftReason,
    required this.scale,
  });

  factory TripBlueprint.fromJson(Map<String, dynamic> data) {
    final List<String> notes = <String>[];
    for (final dynamic note in (data['notes'] as List<dynamic>?) ?? <dynamic>[]) {
      notes.add(note as String);
    }
    return TripBlueprint(
      topViewSvg: data['topViewSvg'] as String,
      sideViewSvg: data['sideViewSvg'] as String,
      plateNumber: (data['vehiclePlateNumber'] as String?) ?? '',
      notes: notes,
      isDraft: (data['isDraft'] as bool?) ?? false,
      draftReason: (data['draftReason'] as String?) ?? '',
      scale: (data['scale'] as String?) ?? '',
    );
  }
}

// Dữ liệu đưa cho trang 3D. Giữ nguyên JSON server trả (không đổi thành model),
// vì trang web đọc đúng các trường đó và app không cần dùng tới từng trường.
class Trip3DData {
  // Một phần tử của plan.trips
  final Map<String, dynamic> trip;
  // order.cargos: tên, khối lượng từng kiện
  final List<dynamic> cargos;

  Trip3DData({required this.trip, required this.cargos});

  // Biển số xe chở, để hiện trên thanh tiêu đề
  String get plateNumber {
    final Map<String, dynamic>? carrier = trip['carrier'] as Map<String, dynamic>?;
    if (carrier == null) {
      return '';
    }
    return (carrier['plateNumber'] as String?) ?? '';
  }
}

// 2D: sơ đồ server vẽ sẵn
Future<TripBlueprint> fetchBlueprint(TripKey key) async {
  return call(
    () {
      return dio.get('/orders/${key.orderId}/shipment-plans/${key.planId}/trips/${key.tripId}/blueprint-svg');
    },
    (dynamic data) {
      return TripBlueprint.fromJson(data as Map<String, dynamic>);
    },
  );
}

// 3D: lấy kế hoạch hiện hành, tìm đúng chuyến; lấy danh sách kiện của đơn
Future<Trip3DData> fetchTrip3DData(TripKey key) async {
  // Kế hoạch đã duyệt; chưa duyệt thì bản mới nhất. Đơn chưa chia chuyến thì 404 PLAN_NOT_FOUND.
  final Map<String, dynamic> plan = await call(
    () {
      return dio.get('/orders/${key.orderId}/shipment-plans/current');
    },
    (dynamic data) {
      return data as Map<String, dynamic>;
    },
  );

  Map<String, dynamic>? trip;
  for (final dynamic row in plan['trips'] as List<dynamic>) {
    final Map<String, dynamic> rowJson = row as Map<String, dynamic>;
    if (rowJson['id'] == key.tripId) {
      trip = rowJson;
      break;
    }
  }
  if (trip == null) {
    // Đơn đã lên lại kế hoạch, chuyến cũ không còn
    throw ApiException(404, 'TRIP_NOT_IN_CURRENT_PLAN', t('plan3d.tripNotInPlan'));
  }

  final List<dynamic> cargos = await call(
    () {
      return dio.get('/Orders/${key.orderId}');
    },
    (dynamic data) {
      return (data as Map<String, dynamic>)['cargos'] as List<dynamic>;
    },
  );

  return Trip3DData(trip: trip, cargos: cargos);
}
