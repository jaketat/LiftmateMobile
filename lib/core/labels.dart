import 'i18n.dart';

/// Đổi mã tiếng Anh từ server sang chữ theo ngôn ngữ máy.
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

// Chữ nằm ở khoá labels.<nhóm>.<mã> trong assets/i18n. Giữ thứ tự mã vì các màn dùng bảng này làm danh sách chọn.
Map<String, String> _labels(String group, List<String> codes) {
  return <String, String>{for (final String code in codes) code: t('labels.$group.$code')};
}

Map<String, String> get orderStatusLabels => _labels('orderStatus', const <String>['Draft', 'Quoted', 'CustomerConfirmed', 'Scheduled', 'InProgress', 'AwaitingFinalization', 'Finalized', 'Invoiced', 'Cancelled']);

Map<String, String> get vehicleBaseTypeLabels => _labels('vehicleBaseType', const <String>['Truck', 'TractorHead', 'Trailer', 'MobileCraneWheeled', 'MobileCraneCrawler', 'Forklift']);

Map<String, String> get vehicleStatusLabels => _labels('vehicleStatus', const <String>['Available', 'InUse', 'UnderMaintenance', 'Suspended']);

Map<String, String> get stopKindLabels => _labels('stopKind', const <String>['Pickup', 'Delivery', 'Via']);

Map<String, String> get tripMilestoneLabels => _labels('tripMilestone', const <String>['Arrived', 'Loaded', 'Unloaded', 'Departed']);

Map<String, String> get crewRoleLabels => _labels('crewRole', const <String>['MainDriver', 'Assistant']);

Map<String, String> get planStatusLabels => _labels('planStatus', const <String>['Draft', 'Approved', 'Superseded']);

Map<String, String> get planTripStatusLabels => _labels('planTripStatus', const <String>['Planned', 'Locked', 'Executed']);

Map<String, String> get verdictLabels => _labels('verdict', const <String>['Pass', 'Fail', 'Unchecked']);

Map<String, String> get vehicleDocumentLabels => _labels('vehicleDocument', const <String>['VehicleInspection', 'TrailerInspection', 'LiftingEquipmentInspection', 'VehicleRegistration', 'CompulsoryInsurance', 'VoluntaryInsurance']);

Map<String, String> get personDocumentLabels => _labels('personDocument', const <String>['OperatorCertificate', 'DriverLicense', 'SafetyCard', 'NationalId', 'CompulsoryInsurance', 'VoluntaryInsurance']);

Map<String, String> get alertLevelLabels => _labels('alertLevel', const <String>['Expired', 'Urgent', 'Reminder']);

Map<String, String> get maintenanceKindLabels => _labels('maintenanceKind', const <String>['Periodic', 'Repair']);

Map<String, String> get maintenanceStatusLabels => _labels('maintenanceStatus', const <String>['Scheduled', 'Completed', 'Cancelled']);

Map<String, String> get breakdownSeverityLabels => _labels('breakdownSeverity', const <String>['MustStop', 'CanContinue']);

Map<String, String> get breakdownStatusLabels => _labels('breakdownStatus', const <String>['Open', 'Acknowledged', 'Resolved']);

Map<String, String> get systemRoleLabels => _labels('systemRole', const <String>['CompanyAdmin', 'Dispatcher', 'Driver']);