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
// Sai mật khẩu hiện tại: errorCode INVALID_CURRENT_PASSWORD
Future<void> changePassword(String currentPassword, String newPassword, String confirmPassword) async {
  // Bước 1: gửi mật khẩu mới
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

  // Bước 2: access token cũ còn cờ "bắt đổi mật khẩu" nên server vẫn chặn các API khác.
  // Xin cặp token mới (không còn cờ) rồi cất vào két, nhớ lưu cả refresh token mới.
  final String? refreshToken = await TokenStore.refresh();
  final Map<String, dynamic> data = await call(
    () {
      return dio.post('/auth/refresh-token', data: {'refreshToken': refreshToken});
    },
    (dynamic data) {
      return data as Map<String, dynamic>;
    },
  );
  await TokenStore.save(data['accessToken'] as String, data['refreshToken'] as String);
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

// Gửi thư đặt lại mật khẩu. Server luôn báo thành công (kể cả email không tồn tại).
// Gửi quá 5 lần mỗi phút thì ApiException 429.
Future<void> forgotPassword(String email) async {
  await call(
    () {
      return dio.post('/auth/forgot-password', data: {'email': email});
    },
    (dynamic data) {
      return null;
    },
  );
}
