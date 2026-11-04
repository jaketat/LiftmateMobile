// Gợi ý giá báo theo cách anh Tiến báo giá: xe × km một chiều, tối thiểu 30% giá 100 km, quá khổ ×1,5
import 'package:flutter_test/flutter_test.dart';
import 'package:liftmate_mobile/features/orders/order_form.dart';
import 'package:liftmate_mobile/features/orders/price_suggestion.dart';

void main() {
  test('Xe to đi 100 km là 8–10 tr, quá khổ 12–15 tr', () {
    final PriceSuggestion normal = suggestPrice(PriceClass.tractor, 100)!;
    expect((normal.low, normal.high, normal.minimum), (8000000, 10000000, false));
    expect(normal.middle, 9000000);
    final PriceSuggestion oversize = suggestPrice(PriceClass.tractor, 100, oversize: true)!;
    expect((oversize.low, oversize.high), (12000000, 15000000));
  });

  test('Đi xa không giảm đơn giá', () {
    final PriceSuggestion far = suggestPrice(PriceClass.tractor, 250)!;
    expect((far.low, far.high), (20000000, 25000000));
  });

  test('Đi gần lấy giá tối thiểu 30% giá 100 km', () {
    final PriceSuggestion near = suggestPrice(PriceClass.tractor, 12)!;
    expect((near.low, near.high, near.minimum), (2400000, 3000000, true));
    final PriceSuggestion small = suggestPrice(PriceClass.truck15, 5)!;
    expect((small.low, small.high), (1700000, 2000000));
  });

  test('Chưa có quãng đường thì không gợi ý', () {
    expect(suggestPrice(PriceClass.truck8, 0), isNull);
  });

  test('Xếp xe theo loại và tải trọng chở', () {
    expect(priceClassFor('Trailer', 32000), PriceClass.tractor);
    expect(priceClassFor('TractorHead', 0), PriceClass.tractor);
    expect(priceClassFor('Truck', 15000), PriceClass.truck15);
    expect(priceClassFor('Truck', 12000), PriceClass.truck15);
    expect(priceClassFor('Truck', 8000), PriceClass.truck8);
    expect(priceClassFor('Truck', 6499), PriceClass.truck5);
    expect(priceClassFor('MobileCraneWheeled', 50000), isNull);
    expect(priceClassFor('Forklift', 3000), isNull);
  });

  test('Quá khổ khi kiện siêu dài, siêu rộng, siêu cao hoặc vượt tải xe', () {
    OrderFormData formWith(CargoDraft cargo) => OrderFormData()..cargos = <CargoDraft>[cargo];
    expect(cargoIsOversize(formWith(CargoDraft(quantity: '1', weightKg: '5000', lengthMm: '6000', widthMm: '2400', heightMm: '2700')), 30000), isFalse);
    expect(cargoIsOversize(formWith(CargoDraft(lengthMm: '21000')), null), isTrue);
    expect(cargoIsOversize(formWith(CargoDraft(widthMm: '2600')), null), isTrue);
    expect(cargoIsOversize(formWith(CargoDraft(heightMm: '2800')), null), isTrue);
    expect(cargoIsOversize(formWith(CargoDraft(quantity: '2', weightKg: '9000')), 15000), isTrue);
    expect(cargoIsOversize(formWith(CargoDraft(quantity: '1', weightKg: '50000')), null), isTrue);
    expect(cargoIsOversize(formWith(CargoDraft(lengthMm: 'abc')), null), isFalse);
  });

  test('Giá thị trường Bắc–Nam 3 tr/tấn', () {
    expect(marketReferencePrice(30000), 90000000);
    expect(marketReferencePrice(1550), 4700000);
  });

  test('Số triệu gọn', () {
    expect(millionsText(8000000, ','), '8');
    expect(millionsText(37500000, ','), '37,5');
    expect(millionsText(1700000, '.'), '1.7');
  });
}
