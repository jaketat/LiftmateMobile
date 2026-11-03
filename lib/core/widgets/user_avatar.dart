// Ảnh đại diện tròn của người dùng. Chưa có ảnh, đang tải hoặc tải lỗi thì hiện chữ viết tắt.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../theme.dart';

/// "Giám đốc Demo" thành "GD": chữ đầu của từ đầu và từ cuối
String nameInitials(String name) {
  final List<String> words = name.trim().split(RegExp(r'\s+'));
  String result = words.first.isNotEmpty ? words.first[0] : '';
  if (words.length > 1) {
    result += words.last[0];
  }
  return result.toUpperCase();
}

/// Khóa lưu ảnh trong máy. URL được ký lại sau mỗi lần gọi /auth/me nên không dùng cả URL làm khóa;
/// đường dẫn cũng không dùng được vì mọi tệp chung một đường dẫn /files/signed. Tên tệp nằm ở tham số fileKeyOrUrl:
/// giữ nguyên khi ký lại, đổi khi người dùng thay ảnh (tên tệp có mã ngẫu nhiên).
String avatarCacheKey(String url) {
  final Uri uri = Uri.parse(url);
  return uri.queryParameters['fileKeyOrUrl'] ?? uri.replace(query: '').toString();
}

/// Ảnh đại diện lưu trong máy. Thay ảnh là ra tên tệp mới, tên cũ không bao giờ đổi nội dung,
/// nên không cần tải lại khi hết hạn server đặt (1 giờ, theo hạn của URL đã ký)
final CacheManager avatarCache = CacheManager(Config(
  'liftmateAvatars',
  stalePeriod: const Duration(days: 365),
  maxNrOfCacheObjects: 20,
  fileService: _KeepFileService(),
));

class _KeepFileService extends HttpFileService {
  @override
  Future<FileServiceResponse> get(String url, {Map<String, String>? headers}) async {
    return _KeepResponse(await super.get(url, headers: headers));
  }
}

class _KeepResponse implements FileServiceResponse {
  final FileServiceResponse response;

  _KeepResponse(this.response);

  @override
  DateTime get validTill => DateTime.now().add(const Duration(days: 365));
  @override
  Stream<List<int>> get content => response.content;
  @override
  int? get contentLength => response.contentLength;
  @override
  int get statusCode => response.statusCode;
  @override
  String? get eTag => response.eTag;
  @override
  String get fileExtension => response.fileExtension;
}

class UserAvatar extends StatelessWidget {
  // Mọi cỡ dùng chung một bản giải mã trong bộ nhớ, đủ nét cho cỡ lớn nhất (104 điểm trên màn 3x)
  static const int decodeWidth = 320;

  final String name;
  // URL đã ký từ /auth/me, hết hạn sau khoảng 1 giờ. Chỉ dùng để tải lần đầu, sau đó ảnh lấy từ máy
  final String? url;
  final double size;

  const UserAvatar({super.key, required this.name, required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    final String? imageUrl = url;
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[Color.lerp(AppColors.navy, Colors.white, 0.14)!, AppColors.navy],
                ),
              ),
              child: Center(
                child: Text(
                  nameInitials(name),
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: size * 0.36),
                ),
              ),
            ),
            if (imageUrl != null)
              CachedNetworkImage(
                imageUrl: imageUrl,
                cacheKey: avatarCacheKey(imageUrl),
                cacheManager: avatarCache,
                fit: BoxFit.cover,
                memCacheWidth: decodeWidth,
                // Ảnh đã có trong máy thì hiện ngay, không làm mờ dần từ chữ viết tắt
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                errorWidget: (BuildContext context, String url, Object error) => const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }
}
