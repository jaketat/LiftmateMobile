// Ảnh bìa trang chủ: ảnh mờ dần vào nền trang, trôi chậm khi cuộn, giãn ra khi kéo xuống.
// Ba nguồn: cảnh xe cẩu vẽ bằng code, ảnh Bing đổi mỗi ngày, ảnh tự tải (chỉ nằm trên máy này).
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/theme.dart';
import '../../core/widgets/ios.dart';
import 'bing_wallpaper.dart';

enum HomeCoverSource { standard, bing, custom }

class HomeCoverStore {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static String _prefix(String userId) => 'home_cover_${userId}_';
  static String _sourceKey(String userId) => 'home_cover_source_$userId';

  static Future<Directory> _directory() => getApplicationDocumentsDirectory();

  static Future<List<File>> _files(String userId) async {
    final Directory directory = await _directory();
    final String prefix = _prefix(userId);
    return <File>[
      for (final FileSystemEntity entity in directory.listSync())
        if (entity is File && entity.uri.pathSegments.last.startsWith(prefix)) entity,
    ];
  }

  /// Nguồn đang chọn. Chưa chọn lần nào thì là ảnh mặc định.
  static Future<HomeCoverSource> source(String userId) async {
    try {
      final String? saved = await _storage.read(key: _sourceKey(userId));
      return HomeCoverSource.values.firstWhere((HomeCoverSource value) => value.name == saved, orElse: () => HomeCoverSource.standard);
    } catch (error) {
      debugPrint('Không đọc được nguồn ảnh bìa: $error');
      return HomeCoverSource.standard;
    }
  }

  static Future<void> setSource(String userId, HomeCoverSource value) async {
    try {
      await _storage.write(key: _sourceKey(userId), value: value.name);
    } catch (error) {
      debugPrint('Không lưu được nguồn ảnh bìa: $error');
    }
  }

  /// Ảnh tự tải. Vẫn giữ khi đổi sang nguồn khác, để quay lại không phải chọn lại.
  static Future<File?> customFile(String userId) async {
    try {
      final List<File> files = await _files(userId);
      return files.isEmpty ? null : files.first;
    } catch (error) {
      debugPrint('Không đọc được ảnh bìa: $error');
      return null;
    }
  }

  /// Chép ảnh vào thư mục của app. Tên có giờ lưu để Flutter không lấy lại ảnh cũ trong bộ nhớ đệm.
  static Future<File> saveCustom(String userId, String sourcePath) async {
    final Directory directory = await _directory();
    final File saved = await File(sourcePath).copy('${directory.path}/${_prefix(userId)}${DateTime.now().millisecondsSinceEpoch}.jpg');
    for (final File old in await _files(userId)) {
      if (old.path != saved.path) await old.delete();
    }
    return saved;
  }

  /// Ảnh cần hiện theo nguồn đang chọn; null là dùng ảnh vẽ sẵn. Không gọi mạng.
  static Future<File?> resolve(String userId) async {
    final File? image = switch (await source(userId)) {
      HomeCoverSource.standard => null,
      HomeCoverSource.custom => await customFile(userId),
      HomeCoverSource.bing => (await BingWallpaper.cached())?.image,
    };
    _lastUser = userId;
    _lastImage = image;
    return image;
  }

  // Ảnh vừa đọc, để trang chủ mở sau màn khóa có đúng ảnh ngay khung đầu thay vì nháy ảnh mặc định
  static String? _lastUser;
  static File? _lastImage;

  static File? lastResolved(String userId) => _lastUser == userId ? _lastImage : null;
}

/// Lớp ảnh bìa nằm sau nội dung trang. [offset] là độ cuộn của trang.
class HomeCover extends StatelessWidget {
  final File? image;
  final double height;
  final ValueListenable<double> offset;

  const HomeCover({super.key, required this.image, required this.height, required this.offset});

  @override
  Widget build(BuildContext context) {
    final Color background = IosColors.groupedBackground;
    final Widget cover = RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          image == null
              ? CustomPaint(painter: DefaultCoverPainter(dark: AppColors.isDark))
              : Image.file(
                  image!,
                  fit: BoxFit.cover,
                  // Ảnh đã giới hạn 1800-1920 khi lưu. Giải mã theo bề ngang màn sẽ làm ảnh ngang bị nhòe khi phóng theo chiều cao.
                  gaplessPlayback: true,
                  errorBuilder: (BuildContext context, Object error, StackTrace? stack) => CustomPaint(painter: DefaultCoverPainter(dark: AppColors.isDark)),
                ),
          // Mờ dần vào nền ở đáy; phủ nhẹ ở đỉnh để chữ thanh trạng thái đọc được trên mọi ảnh
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const <double>[0, 0.18, 0.4, 0.56, 0.82],
                colors: <Color>[
                  background.withValues(alpha: 0.6),
                  background.withValues(alpha: 0),
                  background.withValues(alpha: 0),
                  background.withValues(alpha: 0.72),
                  background,
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: height,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: offset,
          child: cover,
          builder: (BuildContext context, Widget? child) {
            final double value = offset.value;
            // Kéo xuống: giãn từ đỉnh. Cuộn lên: trôi bằng nửa tốc độ nội dung.
            final Matrix4 transform = value < 0
                ? Matrix4.diagonal3Values(1 - value / height, 1 - value / height, 1)
                : Matrix4.translationValues(0, -value * 0.5, 0);
            return Transform(alignment: Alignment.topCenter, transform: transform, child: child);
          },
        ),
      ),
    );
  }
}

/// Ảnh mặc định: xe cẩu lúc bình minh, nền sáng là sáng sớm, nền tối là chập choạng
class DefaultCoverPainter extends CustomPainter {
  final bool dark;

  const DefaultCoverPainter({required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final Rect rect = Offset.zero & size;
    final double ground = h * 0.45;
    final double u = w / 400;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const <double>[0, 0.3, 0.47],
          colors: dark
              ? const <Color>[Color(0xFF0B1436), Color(0xFF3A2C5C), Color(0xFFC8622F)]
              : const <Color>[Color(0xFF7FB2EA), Color(0xFFC9DDF3), Color(0xFFFBD9B0)],
        ).createShader(rect),
    );

    // Mặt trời mọc sau xe
    final Offset sun = Offset(w * 0.27, ground - 26 * u);
    final double sunGlow = 150 * u;
    canvas.drawCircle(
      sun,
      sunGlow,
      Paint()
        ..shader = RadialGradient(
          colors: dark
              ? const <Color>[Color(0xCCFFB066), Color(0x00FFB066)]
              : const <Color>[Color(0xE6FFF1D6), Color(0x00FFF1D6)],
        ).createShader(Rect.fromCircle(center: sun, radius: sunGlow)),
    );

    // Hai lớp đồi xa
    void hills(double base, double rise, Color color) {
      // Kéo xuống tận đáy ảnh để lớp mờ của trang phủ dần lên, không có đường cắt ở chân đồi
      final Path path = Path()
        ..moveTo(0, h)
        ..lineTo(0, base)
        ..cubicTo(w * 0.22, base - rise, w * 0.34, base + rise * 0.3, w * 0.55, base - rise * 0.5)
        ..cubicTo(w * 0.72, base - rise * 1.2, w * 0.86, base + rise * 0.2, w, base - rise * 0.4)
        ..lineTo(w, h)
        ..close();
      canvas.drawPath(path, Paint()..color = color);
    }

    hills(ground - 34 * u, 26 * u, dark ? const Color(0xFF4A2E55) : const Color(0x8C9DB6D6));
    hills(ground - 14 * u, 18 * u, dark ? const Color(0xFF2C1F3F) : const Color(0xB37F9CC0));

    final Color ink = dark ? const Color(0xFF080A16) : const Color(0xFF233B63);
    final Paint fill = Paint()..color = ink;
    // Xe cẩu, gốc tọa độ ở đuôi xe trên mặt đất
    final double x0 = w * 0.1;
    Offset p(double x, double y) => Offset(x0 + x * u, ground - y * u);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromPoints(p(0, 26), p(150, 14)), Radius.circular(2 * u)), fill);
    // Cabin
    canvas.drawPath(
      Path()
        ..moveTo(p(150, 14).dx, p(150, 14).dy)
        ..lineTo(p(150, 54).dx, p(150, 54).dy)
        ..lineTo(p(176, 54).dx, p(176, 54).dy)
        ..lineTo(p(196, 32).dx, p(196, 32).dy)
        ..lineTo(p(196, 14).dx, p(196, 14).dy)
        ..close(),
      fill,
    );
    // Kính cabin bắt màu trời
    canvas.drawPath(
      Path()
        ..moveTo(p(158, 48).dx, p(158, 48).dy)
        ..lineTo(p(174, 48).dx, p(174, 48).dy)
        ..lineTo(p(186, 34).dx, p(186, 34).dy)
        ..lineTo(p(158, 34).dx, p(158, 34).dy)
        ..close(),
      Paint()..color = dark ? const Color(0xFFC8622F) : const Color(0xFFFBD9B0),
    );
    for (final double x in const <double>[26, 52, 170]) {
      canvas.drawCircle(p(x, 9), 9 * u, fill);
      canvas.drawCircle(p(x, 9), 3 * u, Paint()..color = dark ? const Color(0xFF4A2E55) : const Color(0xFF9DB6D6));
    }
    // Chân chống, bệ cẩu, cần cẩu
    canvas.drawRect(Rect.fromPoints(p(92, 14), p(98, 0)), fill);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromPoints(p(66, 44), p(112, 26)), Radius.circular(3 * u)), fill);
    final Paint boom = Paint()
      ..color = ink
      ..strokeWidth = 7 * u
      ..strokeCap = StrokeCap.round;
    final Offset tip = p(236, 92);
    canvas.drawLine(p(86, 38), tip, boom);
    // Cáp và kiện hàng đang nâng
    final Offset hook = p(236, 38);
    canvas.drawLine(tip, hook, Paint()..color = ink..strokeWidth = 1.6 * u);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: p(236, 24), width: 40 * u, height: 28 * u), Radius.circular(3 * u)), fill);
  }

  @override
  bool shouldRepaint(DefaultCoverPainter oldDelegate) => oldDelegate.dark != dark;
}
