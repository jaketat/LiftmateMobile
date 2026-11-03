// Bỏ thông tin đi kèm ảnh (vị trí GPS, thời gian, máy chụp, ảnh nhỏ) trước khi gửi cho dịch vụ AI.
// Cắt thẳng trên file, không nén lại nên ảnh không giảm chất lượng. JPEG giữ lại đúng chiều xoay để AI đọc được chữ.
// Không chắc đã xóa sạch thì báo lỗi chứ không gửi: định dạng lạ hoặc file hỏng đều ném FormatException.
import 'dart:typed_data';

class CleanImage {
  final Uint8List bytes;
  final String fileName;
  // image/jpeg, image/png, image/webp: các loại server nhận
  final String subtype;

  const CleanImage({required this.bytes, required this.fileName, required this.subtype});
}

/// Nhận biết định dạng theo nội dung file, không theo đuôi tên
CleanImage stripImageMetadata(Uint8List bytes) {
  if (_startsWith(bytes, const <int>[0xFF, 0xD8])) {
    return CleanImage(bytes: _stripJpeg(bytes), fileName: 'image.jpg', subtype: 'jpeg');
  }
  if (_startsWith(bytes, const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return CleanImage(bytes: _stripPng(bytes), fileName: 'image.png', subtype: 'png');
  }
  if (_startsWith(bytes, 'RIFF'.codeUnits) && bytes.length >= 12 && _matches(bytes, 8, 'WEBP')) {
    return CleanImage(bytes: _stripWebp(bytes), fileName: 'image.webp', subtype: 'webp');
  }
  throw const FormatException('Định dạng ảnh không hỗ trợ');
}

bool _startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (int i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

bool _matches(Uint8List bytes, int offset, String ascii) {
  if (offset + ascii.length > bytes.length) return false;
  for (int i = 0; i < ascii.length; i++) {
    if (bytes[offset + i] != ascii.codeUnitAt(i)) return false;
  }
  return true;
}

Uint8List _stripJpeg(Uint8List b) {
  final BytesBuilder rest = BytesBuilder(copy: false);
  Uint8List? jfif;
  int? orientation;
  bool anySegment = false;
  int i = 2;
  while (true) {
    if (i + 1 >= b.length || b[i] != 0xFF) throw const FormatException('JPEG hỏng');
    // Các byte FF đệm trước mã đoạn
    while (i + 1 < b.length && b[i + 1] == 0xFF) {
      i++;
    }
    if (i + 1 >= b.length) throw const FormatException('JPEG hỏng');
    final int marker = b[i + 1];

    if (marker == 0xD9) {
      // Hết ảnh chính. Phần sau (ảnh phụ HDR của iPhone, ảnh xem trước) có thông tin riêng nên bỏ luôn.
      final BytesBuilder out = BytesBuilder(copy: false)..add(const <int>[0xFF, 0xD8]);
      if (jfif != null) out.add(jfif);
      if (orientation != null && orientation > 1) out.add(_orientationExif(orientation));
      out
        ..add(rest.takeBytes())
        ..add(const <int>[0xFF, 0xD9]);
      return out.takeBytes();
    }
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      rest.add(Uint8List.sublistView(b, i, i + 2));
      i += 2;
      continue;
    }

    if (i + 3 >= b.length) throw const FormatException('JPEG hỏng');
    final int end = i + 2 + (b[i + 2] << 8 | b[i + 3]);
    if (end > b.length || end < i + 4) throw const FormatException('JPEG hỏng');
    final Uint8List segment = Uint8List.sublistView(b, i, end);

    if (marker == 0xDA) {
      // Dữ liệu ảnh chạy tới mã đoạn kế tiếp; FF 00 và FF D0-D7 nằm trong dữ liệu
      int scan = end;
      while (true) {
        if (scan + 1 >= b.length) throw const FormatException('JPEG hỏng');
        if (b[scan] == 0xFF) {
          final int next = b[scan + 1];
          if (next != 0x00 && !(next >= 0xD0 && next <= 0xD7)) break;
          scan += 2;
        } else {
          scan++;
        }
      }
      rest.add(Uint8List.sublistView(b, i, scan));
      i = scan;
      anySegment = true;
      continue;
    }

    if (marker == 0xE0 && !anySegment && _matches(b, i + 4, 'JFIF')) {
      jfif = segment;
    } else if (marker == 0xE1) {
      if (_matches(b, i + 4, 'Exif\u0000\u0000')) orientation ??= _readOrientation(b, i + 10, end);
    } else if (_keepJpegSegment(b, i, marker)) {
      rest.add(segment);
    }
    anySegment = true;
    i = end;
  }
}

/// Chỉ giữ đoạn cần để hiện đúng ảnh: JFIF, màu (ICC, Adobe), và các đoạn không phải metadata.
/// Bỏ EXIF, XMP (APP1), IPTC (APP13), ghi chú, danh mục ảnh phụ (MPF) và các đoạn APP của hãng.
bool _keepJpegSegment(Uint8List b, int i, int marker) {
  if (marker == 0xFE) return false;
  if (marker < 0xE0 || marker > 0xEF) return true;
  if (marker == 0xE0) return _matches(b, i + 4, 'JFIF');
  if (marker == 0xE2) return _matches(b, i + 4, 'ICC_PROFILE');
  if (marker == 0xEE) return _matches(b, i + 4, 'Adobe');
  return false;
}

int? _readOrientation(Uint8List b, int tiff, int end) {
  if (tiff + 8 > end) return null;
  final Endian endian;
  if (_matches(b, tiff, 'II')) {
    endian = Endian.little;
  } else if (_matches(b, tiff, 'MM')) {
    endian = Endian.big;
  } else {
    return null;
  }
  final ByteData data = ByteData.sublistView(b, tiff, end);
  final int ifd = data.getUint32(4, endian);
  if (ifd + 2 > data.lengthInBytes) return null;
  final int count = data.getUint16(ifd, endian);
  for (int n = 0; n < count; n++) {
    final int entry = ifd + 2 + n * 12;
    if (entry + 12 > data.lengthInBytes) return null;
    if (data.getUint16(entry, endian) == 0x0112) {
      final int value = data.getUint16(entry + 8, endian);
      return value >= 1 && value <= 8 ? value : null;
    }
  }
  return null;
}

/// Đoạn EXIF tối thiểu chỉ có một thẻ chiều xoay
Uint8List _orientationExif(int orientation) {
  return Uint8List.fromList(<int>[
    0xFF, 0xE1, 0x00, 0x22, // APP1, dài 34 byte
    0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // Exif\0\0
    0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08, // TIFF big-endian, IFD0 ở byte 8
    0x00, 0x01, // một thẻ
    0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, // Orientation, kiểu SHORT, một giá trị
    0x00, orientation, 0x00, 0x00, //
    0x00, 0x00, 0x00, 0x00, // hết IFD
  ]);
}

Uint8List _stripPng(Uint8List b) {
  const Set<String> dropped = <String>{'eXIf', 'tEXt', 'zTXt', 'iTXt', 'tIME'};
  final BytesBuilder out = BytesBuilder(copy: false)..add(Uint8List.sublistView(b, 0, 8));
  final ByteData data = ByteData.sublistView(b);
  int i = 8;
  while (true) {
    if (i + 12 > b.length) throw const FormatException('PNG hỏng');
    final int end = i + 12 + data.getUint32(i);
    if (end > b.length) throw const FormatException('PNG hỏng');
    final String type = String.fromCharCodes(b, i + 4, i + 8);
    if (!dropped.contains(type)) out.add(Uint8List.sublistView(b, i, end));
    if (type == 'IEND') return out.takeBytes();
    i = end;
  }
}

Uint8List _stripWebp(Uint8List b) {
  final ByteData data = ByteData.sublistView(b);
  final int riffEnd = 8 + data.getUint32(4, Endian.little);
  if (riffEnd > b.length) throw const FormatException('WebP hỏng');
  final BytesBuilder chunks = BytesBuilder();
  int i = 12;
  while (i < riffEnd) {
    if (i + 8 > riffEnd) throw const FormatException('WebP hỏng');
    final int size = data.getUint32(i + 4, Endian.little);
    final int end = i + 8 + size + (size.isOdd ? 1 : 0);
    if (end > riffEnd) throw const FormatException('WebP hỏng');
    final bool metadata = _matches(b, i, 'EXIF') || _matches(b, i, 'XMP ');
    if (!metadata) {
      final Uint8List chunk = Uint8List.fromList(Uint8List.sublistView(b, i, end));
      // VP8X khai báo có EXIF, XMP ở byte cờ: phải tắt theo
      if (_matches(b, i, 'VP8X') && chunk.length > 8) chunk[8] &= ~0x0C;
      chunks.add(chunk);
    }
    i = end;
  }
  final Uint8List body = chunks.takeBytes();
  final ByteData header = ByteData(12);
  header.setUint32(0, 0x52494646); // RIFF
  header.setUint32(4, body.length + 4, Endian.little);
  header.setUint32(8, 0x57454250); // WEBP
  return (BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(body))
      .takeBytes();
}
