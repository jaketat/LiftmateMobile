// Hàm gọi API đăng nhập. Màn hình gọi qua sessionProvider, không gọi thẳng.

import '../../core/api/api_client.dart';
import '../../core/api/call.dart';
import '../../core/api/token_store.dart';
import '../../core/session.dart';

// Sai mật khẩu → ApiException (401 INVALID_CREDENTIALS, 429 TOO_MANY_ATTEMPTS)
Future<void> login(String identifier, String password) async {
  final String deviceId = await TokenStore.deviceId();

  final Map<String, dynamic> data = await call(
    () {
      return dio.post('/auth/login', data: {
        'identifier': identifier,
        'password': password,
        'deviceId': deviceId,
        'deviceName': 'Android',
        'platform': 'android',
      });
    },
    (dynamic data) {
      return data as Map<String, dynamic>;
    },
  );

  await TokenStore.save(data['accessToken'] as String, data['refreshToken'] as String);
}

// Ai đang đăng nhập + quyền mới nhất
Future<Session> fetchSession() async {
  return call(
    () {
      return dio.get('/auth/me');
    },
    (dynamic data) {
      return Session.fromJson(data as Map<String, dynamic>);
    },
  );
}

// Lỗi từng ô (mật khẩu yếu, xác nhận không khớp) nằm trong ApiException.fieldErrors
Future<void> changePassword(String currentPassword, String newPassword, String confirmPassword) async {
  await call(
    () {
      return dio.post('/auth/change-password', data: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
        'confirmPassword': confirmPassword,
      });
    },
    (dynamic data) {
      return null;
    },
  );
}

Future<void> logout() async {
  final String? refreshToken = await TokenStore.refresh();
  try {
    await call(
      () {
        return dio.post('/auth/logout', data: {'refreshToken': refreshToken});
      },
      (dynamic data) {
        return null;
      },
    );
  } on ApiException {
    // Bỏ qua
  }
  await TokenStore.clear();
}
