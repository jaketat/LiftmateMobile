// Hai file ngôn ngữ phải khớp nhau: thiếu khoá ở en thì máy tiếng Anh lại hiện tiếng Việt.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> read(String code) => jsonDecode(File('assets/i18n/$code.json').readAsStringSync()) as Map<String, dynamic>;

Set<String> placeholders(Object? text) => RegExp(r'\{(\w+)\}').allMatches('$text').map((Match match) => match.group(1)!).toSet();

void main() {
  test('vi và en có cùng bộ khoá, cùng tham số', () {
    final Map<String, dynamic> vi = read('vi');
    final Map<String, dynamic> en = read('en');
    expect(en.keys.toSet(), vi.keys.toSet());
    for (final String key in vi.keys) {
      expect(placeholders(en[key]), placeholders(vi[key]), reason: key);
    }
  });

  test('bản en không còn chữ tiếng Việt', () {
    final RegExp vietnamese = RegExp(r'[ăâđêôơưĂÂĐÊÔƠƯàáảãạằắẳẵặầấẩẫậèéẻẽẹềếểễệìíỉĩịòóỏõọồốổỗộờớởỡợùúủũụừứửữựỳýỷỹỵ]');
    final List<String> left = <String>[
      for (final MapEntry<String, dynamic> entry in read('en').entries)
        if (vietnamese.hasMatch('\${entry.value}')) entry.key,
    ];
    expect(left, isEmpty);
  });
}
