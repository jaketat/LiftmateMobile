//kho luu ma hoa
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
//tao ma uuid
import 'package:uuid/uuid.dart';

class TokenStore {
  static const _s = FlutterSecureStorage();

  //doc ten token theo key
  static Future<String?> access() => _s.read(key: 'access');
  static Future<String?> refresh() => _s.read(key: 'refresh');

  //save key
  static Future<void> save(String access, String refresh) async {
    await _s.write(key: 'access', value: access);
    await _s.write(key: 'refresh', value: refresh);
  }

  //refresh token xoá key cũ
  static Future<void> clear() async {
    await _s.delete(key: 'access');
    await _s.delete(key: 'refresh');
  }

  //lấy deviceId
  static Future<String> deviceId() async {
    final id = await _s.read(key: 'deviceId');
    if (id != null) return id;
    final created = const Uuid().v4();
    await _s.write(key: 'deviceId', value: created);
    return created;
  }
}