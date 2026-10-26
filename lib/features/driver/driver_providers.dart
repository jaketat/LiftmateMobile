// Hộp dữ liệu của app tài xế.
// Riverpod: FutureProvider, AsyncNotifier, Ref
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';

import 'driver_api.dart';

/// T1: mọi chuyến của tôi (7 ngày trước → 30 ngày sau).
/// autoDispose: điều phối có thể vừa gán chuyến, rời khu tài xế thì bỏ, vào lại thì tải mới.
final driverTripsProvider = FutureProvider.autoDispose<List<MyTrip>>((Ref ref) {
  return fetchDriverTrips();
});

/// T5: ảnh và biên bản của một chuyến
final tripDocumentsProvider = FutureProvider.autoDispose.family<List<TripDocument>, String>((Ref ref, String tripId) {
  return fetchTripDocuments(tripId);
});

/// Vị trí hiện tại để vẽ chấm xanh trên bản đồ. Không hỏi quyền ở đây (màn đồng ý mới hỏi):
/// chưa có quyền thì trả null, bản đồ chỉ vẽ các điểm của chuyến.
final myPositionProvider = FutureProvider.autoDispose<Position?>((Ref ref) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return null;
    }
    final LocationPermission permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) {
      return null;
    }
    final Position? last = await Geolocator.getLastKnownPosition();
    if (last != null) {
      return last;
    }
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)),
    );
  } catch (_) {
    return null;
  }
});

/// Trạng thái đồng ý chia sẻ vị trí + "đã từ chối bản điều khoản này" (lưu trong máy,
/// để không hỏi lại mỗi lần mở app; điều khoản đổi bản thì hỏi lại).
class ConsentState {
  final LocationConsent consent;
  final bool declinedThisVersion;

  const ConsentState({required this.consent, required this.declinedThisVersion});

  bool get accepted => consent.accepted;

  // Chưa đồng ý và chưa từ chối bản hiện hành: hiện màn T7
  bool get shouldAsk => !consent.accepted && !declinedThisVersion;
}

const String _declinedKey = 'locationConsentDeclinedVersion';
const FlutterSecureStorage _storage = FlutterSecureStorage();

class ConsentNotifier extends AsyncNotifier<ConsentState> {
  @override
  Future<ConsentState> build() async {
    final LocationConsent consent = await fetchLocationConsent();
    return _withDeclined(consent);
  }

  Future<ConsentState> _withDeclined(LocationConsent consent) async {
    final String? declined = await _storage.read(key: _declinedKey);
    return ConsentState(consent: consent, declinedThisVersion: declined == consent.currentTermsVersion);
  }

  /// Đồng ý với đúng bản điều khoản vừa đọc. Điều khoản đổi giữa chừng: server trả 422
  /// TERMS_VERSION_OUTDATED, màn tải lại rồi cho đọc lại.
  Future<void> accept() async {
    final ConsentState? current = state.value;
    final String? version = current?.consent.currentTermsVersion;
    final LocationConsent saved = await saveLocationConsent(accepted: true, termsVersion: version);
    await _storage.delete(key: _declinedKey);
    state = AsyncData(await _withDeclined(saved));
  }

  /// Rút lại (nút "Tắt"). Gửi lại cùng trạng thái không sao.
  Future<void> revoke() async {
    await saveLocationConsent(accepted: false);
    // Đọc lại từ máy chủ để công tắc hiện đúng trạng thái thật đã lưu
    final LocationConsent fresh = await fetchLocationConsent();
    state = AsyncData(await _withDeclined(fresh));
  }

  /// "Không chia sẻ" ở lần hỏi đầu: không gọi server, chỉ nhớ để khỏi hỏi lại bản này.
  Future<void> decline() async {
    final ConsentState? current = state.value;
    if (current == null) {
      return;
    }
    await _storage.write(key: _declinedKey, value: current.consent.currentTermsVersion);
    state = AsyncData(ConsentState(consent: current.consent, declinedThisVersion: true));
  }

  /// Server báo chưa đồng ý (403 LOCATION_CONSENT_REQUIRED khi gửi vị trí): đọc lại
  Future<void> reload() async {
    state = await AsyncValue.guard(build);
  }
}

final consentProvider = AsyncNotifierProvider<ConsentNotifier, ConsentState>(ConsentNotifier.new);
