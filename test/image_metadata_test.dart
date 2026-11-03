// Ảnh gửi cho AI không được còn vị trí, nhưng phải giữ nguyên dữ liệu ảnh và chiều xoay
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:liftmate_mobile/features/orders/image_metadata.dart';

const String secret = 'SECRET-GPS-20.93-106.61';

List<int> segment(int marker, List<int> payload) {
  final int length = payload.length + 2;
  return <int>[0xFF, marker, length >> 8, length & 0xFF, ...payload];
}

/// EXIF có Orientation ở IFD0 và một vùng giả làm thẻ GPS
List<int> exifPayload({required int orientation, bool littleEndian = false}) {
  final List<int> tiff = littleEndian
      ? <int>[0x49, 0x49, 0x2A, 0x00, 0x08, 0, 0, 0, 0x01, 0x00, 0x12, 0x01, 0x03, 0x00, 0x01, 0, 0, 0, orientation, 0, 0, 0, 0, 0, 0, 0]
      : <int>[0x4D, 0x4D, 0x00, 0x2A, 0, 0, 0, 0x08, 0x00, 0x01, 0x01, 0x12, 0x00, 0x03, 0, 0, 0, 0x01, 0, orientation, 0, 0, 0, 0, 0, 0];
  return <int>[...ascii.encode('Exif'), 0, 0, ...tiff, ...ascii.encode(secret)];
}

// Dữ liệu ảnh có FF 00 và FF D3 như ảnh thật: không được hiểu nhầm là hết đoạn
const List<int> scanHeader = <int>[0xFF, 0xDA, 0x00, 0x08, 1, 1, 0, 0, 0x3F, 0];
const List<int> scanData = <int>[0x12, 0xFF, 0x00, 0x34, 0xFF, 0xD3, 0x56];
final List<int> quant = segment(0xDB, <int>[0, 1, 2, 3]);
final List<int> frame = segment(0xC0, <int>[8, 0, 1, 0, 1, 1, 1, 0x11, 0]);
final List<int> icc = segment(0xE2, <int>[...ascii.encode('ICC_PROFILE'), 0, 1, 1, 9, 9]);
final List<int> adobe = segment(0xEE, <int>[...ascii.encode('Adobe'), 0, 100]);
final List<int> jfif = segment(0xE0, <int>[...ascii.encode('JFIF'), 0, 1, 1, 0, 0, 1, 0, 1, 0, 0]);

Uint8List jpeg({int orientation = 6, bool littleEndian = false, List<int> trailing = const <int>[]}) {
  return Uint8List.fromList(<int>[
    0xFF, 0xD8,
    ...jfif,
    ...segment(0xE1, exifPayload(orientation: orientation, littleEndian: littleEndian)),
    ...segment(0xE1, <int>[...ascii.encode('http://ns.adobe.com/xap/1.0/'), 0, ...ascii.encode(secret)]),
    ...segment(0xE2, <int>[...ascii.encode('MPF'), 0, ...ascii.encode(secret)]),
    ...segment(0xED, ascii.encode('Photoshop 3.0$secret')),
    ...segment(0xFE, ascii.encode(secret)),
    ...icc,
    ...adobe,
    ...quant,
    ...frame,
    ...scanHeader,
    ...scanData,
    0xFF, 0xD9,
    ...trailing,
  ]);
}

bool containsBytes(List<int> haystack, List<int> needle) {
  for (int i = 0; i + needle.length <= haystack.length; i++) {
    int n = 0;
    while (n < needle.length && haystack[i + n] == needle[n]) {
      n++;
    }
    if (n == needle.length) return true;
  }
  return false;
}

void expectNoSecret(List<int> bytes) => expect(containsBytes(bytes, ascii.encode(secret)), isFalse);

List<int> pngChunk(String type, List<int> data) {
  final int n = data.length;
  return <int>[n >> 24, n >> 16 & 255, n >> 8 & 255, n & 255, ...ascii.encode(type), ...data, 1, 2, 3, 4];
}

const List<int> pngSignature = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

List<int> webpChunk(String fourcc, List<int> data) {
  final int n = data.length;
  return <int>[...ascii.encode(fourcc), n & 255, n >> 8 & 255, n >> 16 & 255, n >> 24 & 255, ...data, if (n.isOdd) 0];
}

Uint8List webp(List<int> chunks) {
  final int n = chunks.length + 4;
  return Uint8List.fromList(<int>[...ascii.encode('RIFF'), n & 255, n >> 8 & 255, n >> 16 & 255, n >> 24 & 255, ...ascii.encode('WEBP'), ...chunks]);
}

void main() {
  group('JPEG', () {
    test('Bỏ hết EXIF, XMP, IPTC, ghi chú, MPF; giữ nguyên dữ liệu ảnh và màu', () {
      final CleanImage clean = stripImageMetadata(jpeg());
      expectNoSecret(clean.bytes);
      expect(clean.subtype, 'jpeg');
      for (final List<int> kept in <List<int>>[jfif, icc, adobe, quant, frame, <int>[...scanHeader, ...scanData, 0xFF, 0xD9]]) {
        expect(containsBytes(clean.bytes, kept), isTrue);
      }
      expect(clean.bytes.sublist(0, 2), <int>[0xFF, 0xD8]);
      // JFIF phải đứng ngay sau đầu file
      expect(clean.bytes.sublist(2, 2 + jfif.length), jfif);
    });

    test('Giữ chiều xoay ở cả hai kiểu thứ tự byte', () {
      for (final bool little in <bool>[false, true]) {
        final Uint8List bytes = stripImageMetadata(jpeg(orientation: 6, littleEndian: little)).bytes;
        expect(containsBytes(bytes, <int>[0x01, 0x12, 0x00, 0x03, 0, 0, 0, 1, 0, 6, 0, 0]), isTrue);
        expect(containsBytes(bytes, ascii.encode('Exif')), isTrue);
      }
    });

    test('Ảnh không xoay thì không cần đoạn EXIF nào', () {
      expect(containsBytes(stripImageMetadata(jpeg(orientation: 1)).bytes, ascii.encode('Exif')), isFalse);
    });

    test('Ảnh phụ dán sau cuối file (HDR iPhone) có GPS riêng cũng bị bỏ', () {
      final Uint8List input = jpeg(trailing: <int>[0xFF, 0xD8, ...segment(0xE1, exifPayload(orientation: 1)), 0xFF, 0xD9]);
      final Uint8List output = stripImageMetadata(input).bytes;
      expectNoSecret(output);
      expect(output.sublist(output.length - 2), <int>[0xFF, 0xD9]);
    });

    test('Ảnh nhiều lượt quét (progressive) còn đủ các lượt', () {
      final List<int> second = <int>[...segment(0xC4, <int>[7, 7]), ...scanHeader, 0x77, 0x88];
      final Uint8List input = Uint8List.fromList(<int>[
        0xFF, 0xD8, ...frame, ...scanHeader, ...scanData, ...second, 0xFF, 0xD9,
      ]);
      expect(stripImageMetadata(input).bytes, input);
    });

    test('File hỏng thì báo lỗi, không gửi đi', () {
      expect(() => stripImageMetadata(Uint8List.fromList(<int>[0xFF, 0xD8, 0x00])), throwsFormatException);
      expect(() => stripImageMetadata(Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE1, 0xFF, 0xFF, 1])), throwsFormatException);
      // Mất đoạn cuối
      final Uint8List full = jpeg();
      expect(() => stripImageMetadata(Uint8List.sublistView(full, 0, full.length - 2)), throwsFormatException);
    });

    test('Thẻ chiều xoay sai hoặc EXIF rác không làm hỏng ảnh', () {
      final Uint8List input = Uint8List.fromList(<int>[
        0xFF, 0xD8,
        ...segment(0xE1, <int>[...ascii.encode('Exif'), 0, 0, 1, 2, 3]),
        ...frame, ...scanHeader, ...scanData, 0xFF, 0xD9,
      ]);
      expect(containsBytes(stripImageMetadata(input).bytes, ascii.encode('Exif')), isFalse);
    });
  });

  test('PNG: bỏ eXIf và các đoạn chữ, giữ phần ảnh', () {
    final List<int> ihdr = pngChunk('IHDR', <int>[0, 0, 0, 1]);
    final List<int> idat = pngChunk('IDAT', <int>[9, 9, 9]);
    final Uint8List input = Uint8List.fromList(<int>[
      ...pngSignature,
      ...ihdr,
      ...pngChunk('eXIf', ascii.encode(secret)),
      ...pngChunk('iTXt', ascii.encode(secret)),
      ...pngChunk('tEXt', ascii.encode(secret)),
      ...idat,
      ...pngChunk('IEND', const <int>[]),
      ...ascii.encode(secret),
    ]);
    final CleanImage clean = stripImageMetadata(input);
    expect(clean.subtype, 'png');
    expect(clean.bytes, <int>[...pngSignature, ...ihdr, ...idat, ...pngChunk('IEND', const <int>[])]);
  });

  test('WebP: bỏ EXIF, XMP, tắt cờ và sửa lại độ dài', () {
    final Uint8List input = webp(<int>[
      ...webpChunk('VP8X', <int>[0x0C | 0x10, 0, 0, 0, 1, 2, 3, 4, 5, 6]),
      ...webpChunk('VP8 ', <int>[7, 7, 7]),
      ...webpChunk('EXIF', ascii.encode(secret)),
      ...webpChunk('XMP ', ascii.encode(secret)),
    ]);
    final CleanImage clean = stripImageMetadata(input);
    expect(clean.subtype, 'webp');
    expectNoSecret(clean.bytes);
    expect(clean.bytes, webp(<int>[
      ...webpChunk('VP8X', <int>[0x10, 0, 0, 0, 1, 2, 3, 4, 5, 6]),
      ...webpChunk('VP8 ', <int>[7, 7, 7]),
    ]));
  });

  test('Định dạng lạ (HEIC, GIF) không gửi đi vì không biết có xóa sạch không', () {
    expect(() => stripImageMetadata(Uint8List.fromList(ascii.encode('....ftypheic'))), throwsFormatException);
    expect(() => stripImageMetadata(Uint8List.fromList(ascii.encode('GIF89a'))), throwsFormatException);
    expect(() => stripImageMetadata(Uint8List(0)), throwsFormatException);
  });
}
