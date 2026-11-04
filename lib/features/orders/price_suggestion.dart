// Gợi ý giá báo theo cách anh Tiến báo giá (chốt 2026-11-03): tính theo xe và km một chiều tới điểm trả, chiều về,
// giấy phép, hộ tống đã gồm trong giá; đi xa không giảm; tối thiểu 30% giá 100 km; quá khổ, quá tải nhân 1,5.
// Đơn giá xe tải nhỏ suy từ tỷ lệ giá thị trường theo tải trọng. Tạm để trong app, sau chuyển thành cài đặt công ty ở backend.
import 'dart:math' as math;

import 'order_form.dart';

enum PriceClass { tractor, truck15, truck8, truck5 }

/// Đơn giá thấp, cao (đồng/km)
const Map<PriceClass, (int, int)> pricePerKm = <PriceClass, (int, int)>{
  PriceClass.tractor: (80000, 100000),
  PriceClass.truck15: (55000, 65000),
  PriceClass.truck8: (45000, 55000),
  PriceClass.truck5: (35000, 45000),
};

const double minimumShareOf100Km = 0.3;
const double oversizeFactor = 1.5;
// Vận tải thường chạy Bắc–Nam lấy khoảng 3 tr/tấn: chỉ để so, hiện khi tuyến dài
const int marketPricePerTon = 3000000;
const int marketReferenceMinKm = 1000;

// Ngưỡng siêu trường, siêu trọng như OversizeRules của backend; chiều cao tính thêm sàn mặc định 1.500 mm
const int superLengthMm = 20000;
const int superWidthMm = 2500;
const int superHeightMm = 4200;
const int defaultFloorHeightMm = 1500;
const int superHeavyKg = 48000;

/// Đầu kéo, moóc tính giá xe to; xe tải chia theo tải trọng chở; cẩu, xe nâng chưa có đơn giá
PriceClass? priceClassFor(String baseType, num payloadKg) {
  switch (baseType) {
    case 'TractorHead':
    case 'Trailer':
      return PriceClass.tractor;
    case 'Truck':
      if (payloadKg >= 12000) return PriceClass.truck15;
      if (payloadKg >= 6500) return PriceClass.truck8;
      return PriceClass.truck5;
  }
  return null;
}

/// Làm tròn tới 100 nghìn
int roundPrice(num amount) => (amount / 100000).round() * 100000;

class PriceSuggestion {
  final PriceClass priceClass;
  final int low;
  final int high;
  final bool oversize;
  // Đi ngắn, lấy giá tối thiểu
  final bool minimum;

  const PriceSuggestion({required this.priceClass, required this.low, required this.high, required this.oversize, required this.minimum});

  int get middle => roundPrice((low + high) / 2);
}

PriceSuggestion? suggestPrice(PriceClass priceClass, num distanceKm, {bool oversize = false}) {
  if (distanceKm <= 0) return null;
  final (int lowRate, int highRate) = pricePerKm[priceClass]!;
  final double factor = oversize ? oversizeFactor : 1;
  num price(int rate) => math.max(rate * 100 * minimumShareOf100Km, rate * distanceKm) * factor;
  return PriceSuggestion(
    priceClass: priceClass,
    low: roundPrice(price(lowRate)),
    high: roundPrice(price(highRate)),
    oversize: oversize,
    minimum: distanceKm < 100 * minimumShareOf100Km,
  );
}

/// Hàng quá khổ, quá tải theo số đã nhập: kiện siêu dài, siêu rộng, siêu cao, hoặc tổng khối lượng vượt tải xe, vượt siêu trọng.
/// Ô chưa nhập hay sai thì bỏ qua.
bool cargoIsOversize(OrderFormData form, num? payloadKg) {
  for (final CargoDraft cargo in form.cargos) {
    final num? length = parseNumberInput(cargo.lengthMm, integer: true);
    final num? width = parseNumberInput(cargo.widthMm, integer: true);
    final num? height = parseNumberInput(cargo.heightMm, integer: true);
    if (length != null && !length.isNaN && length > superLengthMm) return true;
    if (width != null && !width.isNaN && width > superWidthMm) return true;
    if (height != null && !height.isNaN && height + defaultFloorHeightMm > superHeightMm) return true;
  }
  final num kg = form.totalKg;
  if (kg > superHeavyKg) return true;
  return payloadKg != null && payloadKg > 0 && kg > payloadKg;
}

/// Giá thị trường Bắc–Nam để so: 3 tr/tấn, làm tròn tới 100 nghìn
int marketReferencePrice(num totalKg) => roundPrice(totalKg / 1000 * marketPricePerTon);

/// 8000000 → "8", 37500000 → "37,5" (triệu, tối đa một số lẻ)
String millionsText(int amount, String decimalSeparator) {
  final double millions = amount / 1000000;
  final String text = millions == millions.roundToDouble() ? millions.round().toString() : millions.toStringAsFixed(1);
  return text.replaceAll('.', decimalSeparator);
}
