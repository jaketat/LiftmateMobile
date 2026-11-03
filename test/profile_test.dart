// Đọc thông tin cá nhân từ /auth/me và chữ viết tắt của ảnh đại diện
import 'package:flutter_test/flutter_test.dart';
import 'package:liftmate_mobile/core/session.dart';
import 'package:liftmate_mobile/core/widgets/user_avatar.dart';

Map<String, dynamic> me({Map<String, dynamic> extra = const <String, dynamic>{}}) {
  return <String, dynamic>{
    'publicId': 'u1',
    'fullName': 'Trần Hữu Hùng',
    'role': 'Driver',
    'permissions': <String>[],
    'mustChangePassword': false,
    'company': <String, dynamic>{'companyName': 'Anh Quân Company'},
    ...extra,
  };
}

void main() {
  test('Session đọc đủ thông tin cá nhân', () {
    final Session session = Session.fromJson(me(extra: <String, dynamic>{
      'username': 'hung',
      'phone': '0900000000',
      'email': 'hung@demo.vn',
      'avatarUrl': 'https://files/a.webp?sig=1',
      'createdAt': '2026-04-01T00:00:00Z',
    }));
    expect(session.username, 'hung');
    expect(session.phone, '0900000000');
    expect(session.email, 'hung@demo.vn');
    expect(session.avatarUrl, 'https://files/a.webp?sig=1');
    expect(session.joinedAt, DateTime.utc(2026, 4, 1));
  });

  test('Thiếu ảnh, email, ngày tham gia vẫn đọc được', () {
    final Session session = Session.fromJson(me());
    expect(session.avatarUrl, isNull);
    expect(session.email, isNull);
    expect(session.joinedAt, isNull);
    expect(session.username, '');
  });

  test('Khóa lưu ảnh giữ nguyên khi URL được ký lại, đổi khi đổi ảnh', () {
    const String first = 'https://app.vn/api/v1/files/signed?fileKeyOrUrl=avatars%2Fa.webp&exp=1&sig=x';
    const String signedAgain = 'https://app.vn/api/v1/files/signed?fileKeyOrUrl=avatars%2Fa.webp&exp=2&sig=y';
    const String otherImage = 'https://app.vn/api/v1/files/signed?fileKeyOrUrl=avatars%2Fb.webp&exp=2&sig=y';
    expect(avatarCacheKey(first), 'avatars/a.webp');
    expect(avatarCacheKey(signedAgain), avatarCacheKey(first));
    expect(avatarCacheKey(otherImage), isNot(avatarCacheKey(first)));
  });

  test('Chữ viết tắt lấy từ đầu và từ cuối', () {
    expect(nameInitials('Trần Hữu Hùng'), 'TH');
    expect(nameInitials('hùng'), 'H');
    expect(nameInitials(''), '');
  });
}
