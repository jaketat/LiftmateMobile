// Biểu tượng hệ thống của Apple (SF Symbols), vd Face ID. Bộ icon của Flutter không có các biểu tượng này.
// iOS vẽ biểu tượng thành ảnh một lần rồi Flutter tô màu, nên không cần view native và trượt trang không bị giật.
// Máy khác iOS, hoặc chưa vẽ xong, thì dùng [fallback].
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const MethodChannel _channel = MethodChannel('liftmate/sf_symbol');
final Map<String, Future<Uint8List?>> _cache = <String, Future<Uint8List?>>{};

Future<Uint8List?> _load(String name) {
  return _cache.putIfAbsent(name, () async {
    try {
      return await _channel.invokeMethod<Uint8List>('png', <String, Object?>{'name': name});
    } catch (error) {
      debugPrint('Không lấy được biểu tượng $name: $error');
      return null;
    }
  });
}

class SfSymbol extends StatelessWidget {
  final String name;
  final double size;
  final Color color;
  final IconData fallback;

  const SfSymbol({super.key, required this.name, required this.size, required this.color, required this.fallback});

  @override
  Widget build(BuildContext context) {
    final Widget icon = Icon(fallback, size: size, color: color);
    if (defaultTargetPlatform != TargetPlatform.iOS) return icon;
    return SizedBox.square(
      dimension: size,
      child: FutureBuilder<Uint8List?>(
        future: _load(name),
        builder: (BuildContext context, AsyncSnapshot<Uint8List?> snapshot) {
          final Uint8List? png = snapshot.data;
          if (png == null) {
            return snapshot.connectionState == ConnectionState.done ? icon : const SizedBox.shrink();
          }
          return Image.memory(png, width: size, height: size, fit: BoxFit.contain, color: color, gaplessPlayback: true);
        },
      ),
    );
  }
}
