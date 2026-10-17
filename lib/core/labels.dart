/// Đổi mã tiếng Anh từ server sang chữ tiếng Việt.
/// Cách dùng: label(orderStatusLabels, order.status)  →  "Khách đã xác nhận"
String label(Map<String, String> labels, String? value) {
  if (value == null) {
    return '';
  }
  final String? text = labels[value];
  if (text == null) {
    // Server thêm mã mới mà bảng chưa có: hiện nguyên mã, không làm văng app
    return value;
  }
  return text;
}

const Map<String, String> orderStatusLabels = {
  'Draft': 'Nháp',
  'Quoted': 'Đã báo giá',
  'CustomerConfirmed': 'Khách đã xác nhận',
  'Scheduled': 'Đã chốt lịch',
  'InProgress': 'Đang thực hiện',
  'AwaitingFinalization': 'Chờ chốt phát sinh',
  'Finalized': 'Đã chốt',
  'Invoiced': 'Đã xuất hóa đơn',
  'Cancelled': 'Đã hủy',
};

const Map<String, String> vehicleBaseTypeLabels = {
  'Truck': 'Xe tải',
  'TractorHead': 'Đầu kéo',
  'Trailer': 'Sơ mi rơ moóc',
  'MobileCraneWheeled': 'Cẩu bánh lốp',
  'MobileCraneCrawler': 'Cẩu bánh xích',
  'Forklift': 'Xe nâng',
};

const Map<String, String> vehicleStatusLabels = {
  'Available': 'Sẵn sàng',
  'InUse': 'Đang chạy',
  'UnderMaintenance': 'Đang bảo dưỡng',
  'Suspended': 'Đình chỉ',
};

const Map<String, String> stopKindLabels = {
  'Pickup': 'Điểm bốc',
  'Delivery': 'Điểm trả',
  'Via': 'Điểm đi qua',
};

const Map<String, String> tripMilestoneLabels = {
  'Arrived': 'Đã đến',
  'Loaded': 'Đã bốc xong',
  'Unloaded': 'Đã dỡ xong',
  'Departed': 'Đã rời điểm',
};

const Map<String, String> crewRoleLabels = {
  'MainDriver': 'Lái chính',
  'Assistant': 'Phụ xe',
};

const Map<String, String> planStatusLabels = {
  'Draft': 'Nháp',
  'Approved': 'Đã duyệt',
  'Superseded': 'Đã bị thay thế',
};

const Map<String, String> planTripStatusLabels = {
  'Planned': 'Máy đề xuất',
  'Locked': 'Đã khóa',
  'Executed': 'Đã chạy',
};

const Map<String, String> verdictLabels = {
  'Pass': 'Đạt',
  'Fail': 'Không đạt',
  'Unchecked': 'Chưa kiểm được',
};

const Map<String, String> vehicleDocumentLabels = {
  'VehicleInspection': 'Đăng kiểm xe',
  'TrailerInspection': 'Đăng kiểm moóc',
  'LiftingEquipmentInspection': 'Kiểm định thiết bị nâng',
  'VehicleRegistration': 'Đăng ký xe',
  'CompulsoryInsurance': 'Bảo hiểm bắt buộc',
  'VoluntaryInsurance': 'Bảo hiểm tự nguyện',
};

const Map<String, String> personDocumentLabels = {
  'OperatorCertificate': 'Chứng chỉ vận hành',
  'DriverLicense': 'Bằng lái',
  'SafetyCard': 'Thẻ an toàn',
  'NationalId': 'Căn cước',
  'CompulsoryInsurance': 'Bảo hiểm bắt buộc',
  'VoluntaryInsurance': 'Bảo hiểm tự nguyện',
};

const Map<String, String> alertLevelLabels = {
  'Expired': 'Đã hết hạn',
  'Urgent': 'Còn ≤ 3 ngày',
  'Reminder': 'Còn ≤ 7 ngày',
};

const Map<String, String> maintenanceKindLabels = {
  'Periodic': 'Định kỳ',
  'Repair': 'Sửa chữa',
};

const Map<String, String> maintenanceStatusLabels = {
  'Scheduled': 'Đã lên lịch',
  'Completed': 'Đã xong',
  'Cancelled': 'Đã hủy',
};

const Map<String, String> breakdownSeverityLabels = {
  'MustStop': 'Phải dừng xe',
  'CanContinue': 'Vẫn chạy được',
};

const Map<String, String> breakdownStatusLabels = {
  'Open': 'Mới',
  'Acknowledged': 'Đã nhận',
  'Resolved': 'Đã xử lý',
};