// Ảnh nền Bing đổi mỗi ngày. API này Microsoft không công bố chính thức nên có thể đổi bất cứ lúc nào:
// lỗi thì giữ ảnh đã tải, chưa có ảnh nào thì trang chủ dùng ảnh mặc định.
// Dùng Dio riêng, không qua dio của app, để token đăng nhập không bao giờ đi sang máy chủ khác.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class BingImage {
  final String startDate;
  final Uri url;
  final String copyright;
  // Lúc Bing đổi sang ảnh kế tiếp; null nếu Bing không cho biết
  final DateTime? nextChangeAt;

  const BingImage({required this.startDate, required this.url, required this.copyright, this.nextChangeAt});

  /// Đọc phản hồi của Bing. Dữ liệu lạ, hoặc địa chỉ không thuộc đường dẫn ảnh của Bing, thì trả null.
  static BingImage? parse(Object? data) {
    if (data is! Map) return null;
    final Object? images = data['images'];
    if (images is! List || images.isEmpty || images.first is! Map) return null;
    final Map<dynamic, dynamic> image = images.first as Map<dynamic, dynamic>;
    final Object? startDate = image['startdate'];
    final Object? urlBase = image['urlbase'];
    if (startDate is! String || !RegExp(r'^\d{8}$').hasMatch(startDate)) return null;
    if (urlBase is! String || !RegExp(r'^/th\?id=[\w.\-]+$').hasMatch(urlBase)) return null;
    return BingImage(
      startDate: startDate,
      url: Uri.parse('https://www.bing.com${urlBase}_1920x1080.jpg'),
      copyright: image['copyright'] is String ? image['copyright'] as String : '',
      nextChangeAt: _nextChange(image['fullstartdate']),
    );
  }

  // fullstartdate là giờ bắt đầu của ảnh, theo UTC, vd 202611020800. Mỗi ảnh dùng 24 giờ.
  static DateTime? _nextChange(Object? fullStart) {
    if (fullStart is! String || !RegExp(r'^\d{12}$').hasMatch(fullStart)) return null;
    int part(int from, int to) => int.parse(fullStart.substring(from, to));
    return DateTime.utc(part(0, 4), part(4, 6), part(6, 8), part(8, 10), part(10, 12)).add(const Duration(days: 1));
  }
}

/// Có nên hỏi Bing không. Chưa tới giờ đổi ảnh thì khỏi hỏi. Đã qua giờ mà Bing chưa đổi thì cách 15 phút hỏi lại một lần,
/// để mở app nhiều lần không gọi mạng liên tục. Đồng hồ máy sai làm giờ đổi xa bất thường thì không tin giờ đó.
bool shouldCheckBing({required DateTime now, required DateTime? nextChangeAt, required DateTime? lastCheckedAt}) {
  if (nextChangeAt != null && now.isBefore(nextChangeAt) && nextChangeAt.difference(now) <= const Duration(hours: 25)) return false;
  if (lastCheckedAt == null || lastCheckedAt.isAfter(now)) return true;
  return now.difference(lastCheckedAt) >= BingWallpaper.recheckAfter;
}

class BingCover {
  final File image;
  final String copyright;

  const BingCover({required this.image, required this.copyright});
}

class BingWallpaper {
  static const Duration recheckAfter = Duration(minutes: 15);
  static const int _maxBytes = 15 * 1024 * 1024;
  static const String _metaName = 'home_bing.json';
  static final Dio _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 30)));

  // Trang chủ và màn cài đặt có thể cùng hỏi: dùng chung một lần gọi
  static Future<BingCover?>? _running;

  /// Ảnh đã tải gần nhất, không gọi mạng
  static Future<BingCover?> cached() async {
    try {
      final Directory directory = await getApplicationDocumentsDirectory();
      final File meta = File('${directory.path}/$_metaName');
      if (!meta.existsSync()) return null;
      final Map<String, dynamic> json = jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
      final File image = File('${directory.path}/${json['file']}');
      if (!image.existsSync()) return null;
      return BingCover(image: image, copyright: (json['copyright'] as String?) ?? '');
    } catch (error) {
      debugPrint('Không đọc được ảnh Bing đã lưu: $error');
      return null;
    }
  }

  /// Tới giờ đổi ảnh thì tải ảnh mới rồi xóa ảnh cũ; chưa tới thì trả ảnh đang có. Ném lỗi nếu mạng hỏng.
  static Future<BingCover?> refresh() {
    return _running ??= _refresh().whenComplete(() => _running = null);
  }

  static Future<BingCover?> _refresh() async {
    final Directory directory = await getApplicationDocumentsDirectory();
    final File meta = File('${directory.path}/$_metaName');
    Map<String, dynamic> saved = <String, dynamic>{};
    if (meta.existsSync()) {
      try {
        saved = jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
      } catch (error) {
        debugPrint('Bỏ thông tin ảnh Bing hỏng: $error');
      }
    }
    final DateTime now = DateTime.now().toUtc();
    final bool check = shouldCheckBing(
      now: now,
      nextChangeAt: DateTime.tryParse('${saved['nextChangeAt']}'),
      lastCheckedAt: DateTime.tryParse('${saved['checkedAt']}'),
    );
    if (!check) return cached();

    final Response<dynamic> response = await _dio.getUri<dynamic>(
      Uri.parse('https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=vi-VN'),
    );
    final BingImage? image = BingImage.parse(response.data is String ? jsonDecode(response.data as String) : response.data);
    if (image == null) throw const FormatException('Bing trả dữ liệu lạ');

    final String fileName = 'home_bing_${image.startDate}.jpg';
    final File target = File('${directory.path}/$fileName');
    if (!target.existsSync() || target.lengthSync() == 0) {
      final Response<List<int>> download = await _dio.getUri<List<int>>(image.url, options: Options(responseType: ResponseType.bytes));
      final List<int> bytes = download.data ?? const <int>[];
      final bool isImage = (download.headers.value(Headers.contentTypeHeader) ?? '').startsWith('image/');
      if (!isImage || bytes.isEmpty || bytes.length > _maxBytes) throw const FormatException('Bing trả ảnh không hợp lệ');
      await target.writeAsBytes(bytes, flush: true);
    }
    await meta.writeAsString(
      jsonEncode(<String, dynamic>{
        'file': fileName,
        'copyright': image.copyright,
        'nextChangeAt': image.nextChangeAt?.toIso8601String(),
        'checkedAt': now.toIso8601String(),
      }),
      flush: true,
    );
    for (final FileSystemEntity entity in directory.listSync()) {
      final String name = entity.uri.pathSegments.last;
      if (entity is File && name.startsWith('home_bing_') && name != fileName) await entity.delete();
    }
    return BingCover(image: target, copyright: image.copyright);
  }
}
