import 'package:intl/intl.dart';

final NumberFormat vietnameseNumberFormat = NumberFormat.decimalPattern('vi');
final DateFormat dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');
final DateFormat dateFormat = DateFormat('dd/MM/yyyy');

/// 6500 → "6.500"
String formatNumber(num? value) {
  if (value == null) {
    return '';
  }
  return vietnameseNumberFormat.format(value);
}

/// 6500 → "6.500 kg"
String formatKg(num? kilograms) {
  if (kilograms == null) {
    return '';
  }
  return '${formatNumber(kilograms)} kg';
}

/// 1500000 → "1.500.000 đ"
String formatMoney(num? amount) {
  if (amount == null) {
    return '';
  }
  return '${formatNumber(amount)} đ';
}

/// 3200, 1800, 2000 → "3.200 × 1.800 × 2.000 mm"
String formatSizeMm(num length, num width, num height) {
  return '${formatNumber(length)} × ${formatNumber(width)} × ${formatNumber(height)} mm';
}

/// Thời điểm: "2026-10-16T00:30:00Z" → "16/10/2026 07:30" (đổi sang giờ của điện thoại)
String formatDateTime(String? isoText) {
  if (isoText == null) {
    return '';
  }
  final DateTime moment = DateTime.parse(isoText).toLocal();
  return dateTimeFormat.format(moment);
}

/// Ngày (không có giờ): "2026-10-16" → "16/10/2026" (KHÔNG đổi múi giờ)
String formatDate(String? dateText) {
  if (dateText == null) {
    return '';
  }
  final DateTime day = DateTime.parse(dateText);
  return dateFormat.format(day);
}

/// Giờ trong ngày: "07:30:00" → "07:30"
String formatTime(String? timeText) {
  if (timeText == null) {
    return '';
  }
  if (timeText.length < 5) {
    return timeText;
  }
  return timeText.substring(0, 5);
}