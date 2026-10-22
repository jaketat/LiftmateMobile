// Hộp dữ liệu cho màn kế hoạch. autoDispose: rời màn thì bỏ, mở lại thì gọi API lấy dữ liệu mới.
// family: mỗi đơn (hoặc mỗi kế hoạch) một hộp riêng.
// Riverpod: FutureProvider, Ref
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
