import 'package:dio/dio.dart';
import '../env.dart';
import 'token_store.dart';

// Gọi khi server từ chối làm mới phiên (token đã bị xóa). Hộp session gắn hàm vào đây.
void Function()? onSessionExpired;

final dio = Dio(BaseOptions(
  baseUrl: Env.apiBase,
  //Sau 15 giây chưa kết nối được thì báo lỗi, không bắt người dùng chờ mãi
  connectTimeout: const Duration(seconds: 15),
  //Chờ server trả lời tối đa 60 giây.
  receiveTimeout: const Duration(seconds: 60),
))..interceptors.add(AuthInterceptor());

//queue chạy lần lượt ko song song
class AuthInterceptor extends QueuedInterceptor{
  // 2 API không gắn token: đăng nhập (chưa có token)
  // và làm mới phiên (token  đã hết hạn)
  static const _noAuth = ['/auth/login', '/auth/refresh-token'];
  final _retry = Dio();
  // Chạy trước mỗi request: đọc token, gắn vào header
  @override
  Future<void> onRequest(RequestOptions o, RequestInterceptorHandler h) async {
    final t = await TokenStore.access();
    if (t != null && !_noAuth.contains(o.path)) {
      o.headers['Authorization'] = 'Bearer $t';
    }
    h.next(o);
  }

  // onError tự chạy mỗi khi một request bị lỗi
  @override
  Future<void> onError(DioException e, ErrorInterceptorHandler h) async {
    final o = e.requestOptions;
    if (e.response?.statusCode != 401 || _noAuth.contains(o.path)) return h.next(e);

    try {
      // Request khác vừa làm mới phiên trong lúc request này chờ: chỉ cần gửi lại với token mới
      //gia sử 2 API gọi cùng lúc, cả 2 đều gặp 401
      final current = await TokenStore.access();
      if (current != null && o.headers['Authorization'] != 'Bearer $current') {
        o.headers['Authorization'] = 'Bearer $current';
        return h.resolve(await _retry.fetch(o));
      }

      final rt = await TokenStore.refresh();
      if (rt == null) return h.next(e);

      final r = await Dio(BaseOptions(baseUrl: Env.apiBase))
          .post('/auth/refresh-token', data: {'refreshToken': rt});
      final d = r.data['data'];
      await TokenStore.save(d['accessToken'], d['refreshToken']);

      o.headers['Authorization'] = 'Bearer ${d['accessToken']}';
      h.resolve(await _retry.fetch(o));
    } on DioException catch (err) {
      // Server từ chối refresh token (401: hết hạn, bị thu hồi, TOKEN_COMPROMISED) thì xóa token
      // và báo hộp session. Mất mạng hay server lỗi 500 thì GIỮ token, có mạng lại dùng tiếp.
      if (err.requestOptions.path == '/auth/refresh-token' && err.response?.statusCode == 401) {
        await TokenStore.clear();
        if (onSessionExpired != null) {
          onSessionExpired!();
        }
      }
      h.next(err);
    }
  }
}