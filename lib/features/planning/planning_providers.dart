// Hộp dữ liệu cho màn kế hoạch. autoDispose: rời màn thì bỏ, mở lại thì gọi API lấy dữ liệu mới.
// family: mỗi đơn (hoặc mỗi kế hoạch) một hộp riêng.
// Riverpod: FutureProvider, Ref
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/call.dart';
import '../../core/i18n.dart';
import '../plan_3d/plan_3d_api.dart';
import 'planning_api.dart';

final currentPlanProvider = FutureProvider.autoDispose.family<ShipmentPlan, String>((Ref ref, String orderId) {
  return fetchCurrentPlan(orderId);
});

final costTotalProvider = FutureProvider.autoDispose.family<num?, PlanKey>((Ref ref, PlanKey key) {
  return fetchCostTotal(key);
});

// Chi tiết tiền dầu (màn K3). Khác costTotalProvider ở trên: lỗi thì để màn hiện câu lỗi và nút "Thử lại"
final costEstimateProvider = FutureProvider.autoDispose.family<CostEstimate, PlanKey>((Ref ref, PlanKey key) {
  return fetchCostEstimate(key);
});

// Một chuyến trong kế hoạch hiện hành, kèm kế hoạch chứa nó (màn K2)
class PlanTripView {
  final ShipmentPlan plan;
  final PlanTrip trip;

  PlanTripView({required this.plan, required this.trip});
}

final planTripProvider = FutureProvider.autoDispose.family<PlanTripView, TripKey>((Ref ref, TripKey key) async {
  final ShipmentPlan plan = await fetchCurrentPlan(key.orderId);
  for (final PlanTrip trip in plan.trips) {
    if (trip.id == key.tripId) {
      return PlanTripView(plan: plan, trip: trip);
    }
  }
  // Đơn đã lên lại kế hoạch, chuyến cũ không còn
  throw ApiException(
    404,
    'TRIP_NOT_IN_CURRENT_PLAN',
    t('planning.tripNotInPlan'),
  );
});
