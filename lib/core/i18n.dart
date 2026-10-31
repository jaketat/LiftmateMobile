// Đa ngôn ngữ theo ngôn ngữ của máy. Chuỗi nằm trong assets/i18n/<mã>.json (khóa phẳng, vd "trips.title").
// Máy đặt tiếng Anh thì dùng en.json; mọi ngôn ngữ khác dùng tiếng Việt. Khóa thiếu ở en.json thì lấy tiếng Việt.
//
// Dùng:  t('trips.title')                      → "Chuyến của tôi"
//        t('trips.today', {'count': 2})        → "Hôm nay · 2"
//        tEnum('crewRole', 'MainDriver')        → "Lái chính"
import 'dart:convert';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/services.dart' show rootBundle;

class I18n {
  static const List<String> supported = <String>['vi', 'en'];
  static const String fallback = 'vi';

  static String lang = fallback;
  static Map<String, String> _strings = <String, String>{};
  static Map<String, String> _fallback = <String, String>{};

  static Locale get locale => Locale(lang);

  /// Gọi một lần trước runApp (và khi người dùng đổi ngôn ngữ máy)
  static Future<void> load([Locale? device]) async {
    final String code = (device ?? PlatformDispatcher.instance.locale).languageCode;
    lang = supported.contains(code) ? code : fallback;
    _fallback = await _read(fallback);
    _strings = lang == fallback ? _fallback : await _read(lang);
  }

  /// Cho test: nạp sẵn chuỗi (vd đọc trực tiếp assets/i18n/vi.json) mà không cần rootBundle
  static void useStrings(Map<String, String> strings, {String language = fallback}) {
    lang = language;
    _fallback = strings;
    _strings = strings;
  }

  static Future<Map<String, String>> _read(String code) async {
    try {
      final Map<String, dynamic> raw =
          jsonDecode(await rootBundle.loadString('assets/i18n/$code.json')) as Map<String, dynamic>;
      return raw.map((String key, dynamic value) => MapEntry<String, String>(key, value.toString()));
    } catch (_) {
      return <String, String>{};
    }
  }

  static String get(String key, [Map<String, Object?> args = const <String, Object?>{}]) {
    String text = _strings[key] ?? _fallback[key] ?? key;
    args.forEach((String name, Object? value) {
      text = text.replaceAll('{$name}', '${value ?? ''}');
    });
    return text;
  }

  static bool has(String key) => _strings.containsKey(key) || _fallback.containsKey(key);
}

/// Chuỗi theo ngôn ngữ máy; {tên} trong chuỗi được thay bằng args
String t(String key, [Map<String, Object?> args = const <String, Object?>{}]) => I18n.get(key, args);

/// Nhãn của một giá trị liệt kê từ server, vd tEnum('orderStatus', 'Scheduled').
/// Không có khóa thì trả lại chính giá trị (không bao giờ hiện khóa thô).
String tEnum(String group, String? value) {
  if (value == null || value.isEmpty) return '';
  final String key = 'enum.$group.$value';
  return I18n.has(key) ? I18n.get(key) : value;
}
