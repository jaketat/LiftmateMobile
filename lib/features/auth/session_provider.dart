// sessionProvider: hộp giữ "ai đang đăng nhập". Đổi state thì mọi màn ref.watch tự vẽ lại.
// 4 trạng thái: đang tải | null (chưa đăng nhập) | Session (đã đăng nhập) | lỗi (mất mạng)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/call.dart';
import '../../core/api/token_store.dart';
import '../../core/session.dart';
import 'auth_api.dart';

// Tạo hộp. SessionNotifier lo việc, đồ trong hộp kiểu Session? (null = chưa đăng nhập)
final AsyncNotifierProvider<SessionNotifier, Session?> sessionProvider =
    AsyncNotifierProvider<SessionNotifier, Session?>(SessionNotifier.new);

class SessionNotifier extends AsyncNotifier<Session?> {
  // Riverpod tự gọi lúc mở app (lần đầu có màn đọc hộp)
  @override
  Future<Session?> build() async {
    // Chưa từng đăng nhập thì khỏi gọi API
    final String? refreshToken = await TokenStore.refresh();
    if (refreshToken == null) {
      return null;
    }

    try {
      return await fetchSession();
    } on ApiException catch (error) {
      // 401 = refresh token hết hạn / bị thu hồi → coi như chưa đăng nhập
      if (error.status == 401) {
        await TokenStore.clear();
        return null;
      }
      // Mất mạng, server bận → trạng thái lỗi, màn chờ hiện "Thử lại"
      rethrow;
    }
  }

  // Sai mật khẩu thì ném ApiException, hộp giữ nguyên, màn đăng nhập hiện lỗi
  Future<void> signIn(String identifier, String password) async {
    await login(identifier, password);
    final Session session = await fetchSession();
    state = AsyncData(session);
  }

  // Đổi mật khẩu rồi hỏi lại /auth/me để mustChangePassword thành false, bảo vệ ở router thả ra.
  // Lỗi (sai mật khẩu hiện tại, mật khẩu yếu) thì ném ApiException, hộp giữ nguyên.
  Future<void> updatePassword(String currentPassword, String newPassword, String confirmPassword) async {
    await changePassword(currentPassword, newPassword, confirmPassword);
    await reload();
  }

  // Gọi lại /auth/me để lấy tên, quyền, cờ đổi mật khẩu mới nhất
  Future<void> reload() async {
    final Session session = await fetchSession();
    state = AsyncData(session);
  }

  // Hộp = null → router tự về /login
  Future<void> signOut() async {
    await logout();
    state = const AsyncData(null);
  }
}
