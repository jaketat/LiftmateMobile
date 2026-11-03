// Bản đang nhập dở của form tạo đơn, tự lưu trong kho mã hóa của máy, mỗi tài khoản một bản.
// Không tạo đơn trên server: form chưa đủ khách, điểm dừng thì server không nhận, và mỗi lần lưu sẽ thành một đơn rác.
// Giữ cả Idempotency-Key: nếu app tắt ngay sau khi gửi, lần gửi lại không tạo trùng đơn.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'order_form.dart';
import 'orders_api.dart';

class SavedOrderDraft {
  final OrderFormData form;
  final String idempotencyKey;
  final String quotedText;
  // Tuyến đã tính: khỏi gọi lại Vietmap (tính lượt) khi mở lại
  final String? routeKey;
  final RouteEstimate? route;
  final DateTime? savedAt;

  const SavedOrderDraft({required this.form, required this.idempotencyKey, required this.quotedText, this.routeKey, this.route, this.savedAt});

  /// Dữ liệu cần giữ, chưa gồm giờ lưu: so chuỗi này để biết có đổi gì không
  String encodeBody() {
    return jsonEncode(<String, dynamic>{
      'v': OrderDraftStore.version,
      'idempotencyKey': idempotencyKey,
      'quotedText': quotedText,
      'form': form.toDraft(),
      if (route != null && routeKey != null) 'routeKey': routeKey,
      if (route != null && routeKey != null) 'route': route!.toJson(),
    });
  }

  /// File hỏng hoặc khác phiên bản thì ném lỗi; OrderDraftStore.load bỏ bản đó
  factory SavedOrderDraft.decode(String raw) {
    final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
    if (json['v'] != OrderDraftStore.version) throw const FormatException('Khác phiên bản');
    final Map<String, dynamic>? route = json['route'] as Map<String, dynamic>?;
    return SavedOrderDraft(
      form: OrderFormData.fromDraft(json['form'] as Map<String, dynamic>),
      idempotencyKey: json['idempotencyKey'] as String,
      quotedText: (json['quotedText'] as String?) ?? '',
      routeKey: json['routeKey'] as String?,
      route: route == null ? null : RouteEstimate.fromJson(route),
      savedAt: DateTime.tryParse((json['savedAt'] as String?) ?? ''),
    );
  }
}

class OrderDraftStore {
  static const int version = 1;
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  // Ghi lần lượt: lệnh xóa sau khi tạo đơn xong không bị lệnh ghi đang chạy đè lại
  static Future<void> _queue = Future<void>.value();

  static String _key(String userId) => 'order_draft_$userId';

  static Future<void> _enqueue(Future<void> Function() task) {
    return _queue = _queue.then((_) => task()).catchError((Object error) {
      // Lưu tạm mà lỗi thì lần đổi sau lưu lại, không làm phiền người đang nhập
      debugPrint('Không lưu được nháp đơn: $error');
    });
  }

  static Future<void> save(String userId, String body) {
    final Map<String, dynamic> json = jsonDecode(body) as Map<String, dynamic>;
    json['savedAt'] = DateTime.now().toUtc().toIso8601String();
    final String value = jsonEncode(json);
    return _enqueue(() => _storage.write(key: _key(userId), value: value));
  }

  static Future<void> clear(String userId) => _enqueue(() => _storage.delete(key: _key(userId)));

  static Future<SavedOrderDraft?> load(String userId) async {
    await _queue;
    try {
      final String? raw = await _storage.read(key: _key(userId));
      return raw == null ? null : SavedOrderDraft.decode(raw);
    } catch (error) {
      debugPrint('Bỏ nháp đơn không đọc được: $error');
      await clear(userId);
      return null;
    }
  }
}
