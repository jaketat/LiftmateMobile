// Các hộp dữ liệu của 9 màn bảo hồng - bảo trì. Màn hình ref.watch hộp nào thì hộp đó tự gọi API.
//
// Riverpod: FutureProvider, Ref
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/paged_result.dart';
import 'maintenance_api.dart';

// Bộ lọc truyền vào hộp phân trang. Record (Dart) so sánh bằng giá trị:
// đổi bộ lọc là ra hộp mới, giữ nguyên thì không gọi lại API.
typedef BreakdownFilter = ({int pageNumber, String status, bool openOnly, String vehicleId});
typedef MaintenanceFilter = ({int pageNumber, String status, String kind, String searchTerm, bool overdueOnly, String vehicleId});
typedef CostRange = ({String from, String to});

// ---------------------------------------------------------------- T6: tài xế

/// T6: 50 báo của tôi gần nhất.
/// autoDispose: báo mới có thể vừa được gửi từ máy khác, rời màn thì bỏ hộp, vào lại thì gọi API lại.
final FutureProvider<List<BreakdownReport>> myBreakdownsProvider =
    FutureProvider.autoDispose<List<BreakdownReport>>((Ref ref) {
  return fetchMyBreakdowns();
});

/// T6: chuyến của tôi. Dùng cho tiêu đề màn báo hồng và danh sách chọn chuyến.
/// Server không có API lấy đúng một chuyến nên phải tải cả danh sách rồi tìm theo publicId.
///
/// PHẢI autoDispose: điều phối có thể vừa gán chuyến cho tôi xong. Nếu hộp này giữ kết quả
/// cũ thì màn báo hồng sẽ mãi báo "chưa có chuyến" dù server đã có.
final myTripsProvider = FutureProvider.autoDispose<List<MyTripBrief>>((Ref ref) {
  return fetchMyTrips();
});

// ------------------------------------------------- Q1: quản lý bảo hồng

final breakdownsPageProvider =
    FutureProvider.autoDispose.family<PagedResult<BreakdownReport>, BreakdownFilter>(
        (Ref ref, BreakdownFilter filter) {
  return fetchBreakdownPage(
    pageNumber: filter.pageNumber,
    status: filter.status,
    openOnly: filter.openOnly,
    vehicleId: filter.vehicleId,
  );
});

final breakdownProvider = FutureProvider.autoDispose.family<BreakdownReport, String>((Ref ref, String id) {
  return fetchBreakdown(id);
});

/// Q1: số báo chưa đóng, để đếm trên nút lọc.
final openBreakdownCountProvider = FutureProvider.autoDispose<int>((Ref ref) {
  return fetchOpenBreakdownCount();
});

/// Q1: lịch sửa chữa của xe, làm ô chọn khi đóng báo hồng.
final vehicleMaintenanceProvider =
    FutureProvider.autoDispose.family<List<MaintenanceRecord>, String>((Ref ref, String vehicleId) {
  return fetchVehicleMaintenance(vehicleId);
});

// ------------------------------------------------------------- M1, M2, M3

final maintenancePageProvider =
    FutureProvider.autoDispose.family<PagedResult<MaintenanceRecord>, MaintenanceFilter>(
        (Ref ref, MaintenanceFilter filter) {
  return fetchMaintenancePage(
    pageNumber: filter.pageNumber,
    status: filter.status,
    kind: filter.kind,
    searchTerm: filter.searchTerm,
    overdueOnly: filter.overdueOnly,
    vehicleId: filter.vehicleId,
  );
});

final maintenanceProvider =
    FutureProvider.autoDispose.family<MaintenanceRecord, String>((Ref ref, String id) {
  return fetchMaintenance(id);
});

/// M2: danh sách xe để chọn khi lập lịch. Danh sách ngắn nên giữ suốt phiên làm việc.
final vehiclesProvider = FutureProvider<List<VehicleOption>>((Ref ref) {
  return fetchVehicles();
});

// ------------------------------------------------------------- M4 và M5

/// M4: xe sắp hoặc đã đến hạn. Dùng cho cả dải cảnh báo ở M1 lẫn màn M4.
final dueAlertsProvider = FutureProvider<List<MaintenanceDueAlert>>((Ref ref) {
  return fetchDueAlerts();
});

final maintenancePlanProvider =
    FutureProvider.autoDispose.family<VehicleMaintenancePlan, String>((Ref ref, String vehicleId) {
  return fetchMaintenancePlan(vehicleId);
});

// ------------------------------------------------------------------- M6

final costSummaryProvider = FutureProvider.autoDispose.family<MaintenanceCostSummary, CostRange>(
    (Ref ref, CostRange range) {
  return fetchCostSummary(range.from, range.to);
});