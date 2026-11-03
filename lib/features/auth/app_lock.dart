// Khóa app bằng Face ID / vân tay. Bật thì mở app dừng ở màn đăng nhập, xác thực xong mới vào; tắt thì vào thẳng.
// Chỉ khóa giao diện: phiên đăng nhập vẫn giữ, nên trong lúc khóa app không đăng xuất và không mất token.
// Luôn đăng nhập được bằng mật khẩu, phòng khi sinh trắc hỏng hoặc bị máy khóa do sai nhiều lần.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';

import '../../core/i18n.dart';
import '../../core/menu/menu_items.dart';
import '../../core/session.dart';
import '../../core/widgets/sf_symbol.dart';
import 'session_provider.dart';

/// Rời app quá lâu thì khóa lại. Không khóa ngay vì tài xế hay chuyển sang app bản đồ, gọi điện rồi quay về ngay.
const Duration appLockGrace = Duration(minutes: 5);

enum BiometricKind { none, notEnrolled, faceId, touchId, fingerprint }

enum BiometricResult { success, cancelled, failed }

extension BiometricKindName on BiometricKind {
  /// Máy dùng được ngay. Chưa cài hoặc không hỗ trợ thì không hỏi, không hiện nút.
  bool get isUsable => this == BiometricKind.faceId || this == BiometricKind.touchId || this == BiometricKind.fingerprint;

  String get displayName {
    return switch (this) {
      BiometricKind.faceId => t('appLock.faceId'),
      BiometricKind.touchId => t('appLock.touchId'),
      _ => t('appLock.fingerprint'),
    };
  }
}

/// Biểu tượng đúng của Apple cho Face ID, Touch ID; Android dùng biểu tượng vân tay
class BiometricIcon extends StatelessWidget {
  final BiometricKind kind;
  final double size;
  final Color color;

  const BiometricIcon({super.key, required this.kind, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return switch (kind) {
      BiometricKind.faceId => SfSymbol(name: 'faceid', size: size, color: color, fallback: Icons.face_outlined),
      BiometricKind.touchId => SfSymbol(name: 'touchid', size: size, color: color, fallback: Icons.fingerprint),
      _ => Icon(Icons.fingerprint, size: size, color: color),
    };
  }
}

class BiometricAuth {
  const BiometricAuth();

  /// Máy có gì để dùng. Lỗi khi hỏi máy thì coi như không có, app chạy như khi tắt tính năng.
  Future<BiometricKind> kind() async {
    final LocalAuthentication auth = LocalAuthentication();
    try {
      if (!await auth.isDeviceSupported()) return BiometricKind.none;
      final List<BiometricType> available = await auth.getAvailableBiometrics();
      if (available.isEmpty) return BiometricKind.notEnrolled;
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        return available.contains(BiometricType.face) ? BiometricKind.faceId : BiometricKind.touchId;
      }
      return BiometricKind.fingerprint;
    } catch (error) {
      debugPrint('Không hỏi được sinh trắc của máy: $error');
      return BiometricKind.none;
    }
  }

  Future<BiometricResult> authenticate() async {
    try {
      final bool ok = await LocalAuthentication().authenticate(
        localizedReason: t('appLock.reason'),
        // Không cho dùng mật mã máy thay thế: lối dự phòng là mật khẩu tài khoản ngay trên màn đăng nhập
        biometricOnly: true,
        authMessages: <AuthMessages>[
          IOSAuthMessages(cancelButton: t('common.cancel')),
          AndroidAuthMessages(signInTitle: t('appLock.promptTitle'), cancelButton: t('common.cancel')),
        ],
      );
      return ok ? BiometricResult.success : BiometricResult.cancelled;
    } on LocalAuthException catch (error) {
      if (error.code == LocalAuthExceptionCode.userCanceled ||
          error.code == LocalAuthExceptionCode.systemCanceled ||
          error.code == LocalAuthExceptionCode.timeout) {
        return BiometricResult.cancelled;
      }
      debugPrint('Xác thực sinh trắc lỗi: ${error.code}');
      return BiometricResult.failed;
    } catch (error) {
      debugPrint('Xác thực sinh trắc lỗi: $error');
      return BiometricResult.failed;
    }
  }
}

final Provider<BiometricAuth> biometricAuthProvider = Provider<BiometricAuth>((Ref ref) => const BiometricAuth());

final FutureProvider<BiometricKind> biometricKindProvider = FutureProvider<BiometricKind>((Ref ref) {
  return ref.watch(biometricAuthProvider).kind();
});

/// Tài xế không dùng khóa app: khóa lúc mở app sẽ làm chậm việc gửi vị trí, vì chỉ vào trang chủ mới bắt đầu gửi.
/// Quản lý có hồ sơ tài xế vẫn dùng được, vì họ dùng giao diện quản lý.
bool canUseAppLock(Session session) => !usesDriverMenu(session);

class AppLockState {
  // Tài khoản đã bật khóa trên máy này. Người khác đăng nhập trên cùng máy thì không bị ảnh hưởng.
  final String? enabledFor;
  final bool locked;

  const AppLockState({required this.enabledFor, required this.locked});

  bool isEnabledFor(String? userId) => userId != null && userId.isNotEmpty && enabledFor == userId;

  bool isLockedFor(String? userId) => locked && isEnabledFor(userId);

  /// Dùng chỗ này để quyết định có chặn không: tài xế đã bật từ trước (vd vừa đổi vai trò) cũng bỏ qua
  bool blocks(Session? session) => session != null && canUseAppLock(session) && isLockedFor(session.userId);
}

class AppLockNotifier extends AsyncNotifier<AppLockState> {
  static const String _key = 'app_lock_user';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  DateTime? _leftAt;
  String? _returnTo;

  @override
  Future<AppLockState> build() async {
    String? enabledFor;
    try {
      enabledFor = await _storage.read(key: _key);
    } catch (error) {
      debugPrint('Không đọc được cài đặt khóa app: $error');
    }
    return AppLockState(enabledFor: enabledFor, locked: enabledFor != null);
  }

  Future<void> enable(String userId) async {
    await _storage.write(key: _key, value: userId);
    state = AsyncData<AppLockState>(AppLockState(enabledFor: userId, locked: false));
  }

  Future<void> disable() async {
    await _storage.delete(key: _key);
    state = const AsyncData<AppLockState>(AppLockState(enabledFor: null, locked: false));
  }

  /// Xác thực xong hoặc đăng nhập đúng mật khẩu
  void unlock() {
    final AppLockState? current = state.value;
    if (current != null && current.locked) {
      state = AsyncData<AppLockState>(AppLockState(enabledFor: current.enabledFor, locked: false));
    }
  }

  void noteLeftApp(DateTime now) => _leftAt ??= now;

  /// Quay lại app sau quá lâu thì khóa, nhớ màn đang đứng để mở khóa xong trả về đó
  void noteReturned(DateTime now, String currentLocation) {
    final DateTime? leftAt = _leftAt;
    _leftAt = null;
    final AppLockState? current = state.value;
    if (leftAt == null || current == null || current.locked) return;
    if (now.difference(leftAt) < appLockGrace) return;
    final Session? session = ref.read(sessionProvider).value;
    if (session == null || !canUseAppLock(session) || !current.isEnabledFor(session.userId)) return;
    _returnTo = currentLocation;
    state = AsyncData<AppLockState>(AppLockState(enabledFor: current.enabledFor, locked: true));
  }

  String? takeReturnLocation() {
    final String? location = _returnTo;
    _returnTo = null;
    return location;
  }
}

final AsyncNotifierProvider<AppLockNotifier, AppLockState> appLockProvider =
    AsyncNotifierProvider<AppLockNotifier, AppLockState>(AppLockNotifier.new);
