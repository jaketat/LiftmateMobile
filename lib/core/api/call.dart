import 'package:dio/dio.dart';

class ApiException implements Exception{
  final int? status;                    // mã HTTP: 400, 404, 422... null nếu mất mạng
  final String? code;                   // errorCode, ví dụ "PLAN_NOT_FOUND"
  final String message;                 // câu hiện cho người dùng
  final Map<String, String> fieldErrors; // tên ô -> lỗi của ô đó

  ApiException(this.status, this.code, this.message, [this.fieldErrors = const {}]);

  @override
  String toString() => message;
}

Future<T> call<T>(Future<Response> Function() send, T Function(dynamic data) parse) async {
  try {
    final r = await send();
    return parse(r.data['data']);
  } on DioException catch (e) {
    throw _toApiException(e);
  }
}

ApiException _toApiException(DioException e) {
  final status = e.response?.statusCode;
  final body = e.response?.data;

  // 1. Không có phản hồi: mất mạng, quá thời gian chờ
  if (e.response == null) {
    return ApiException(null, null, 'Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.');
  }

  // 2. Có phản hồi nhưng không phải JSON của backend (nginx trả trang lỗi HTML)
  if (body is! Map) {
    return ApiException(status, null, 'Máy chủ đang bận (mã $status). Thử lại sau.');
  }

  // 3. Lỗi 500: chỉ hiện mã tra cứu
  if (status == 500) {
    final id = (body['correlationId'] ?? '').toString();
    final shortId = id.length >= 8 ? id.substring(0, 8): id;
    return ApiException(500, null, 'Lỗi hệ thống. Mã tra cứu: $shortId');
  }

  // 4. Lỗi thường (400, 403, 404, 409, 422, 429): server đã viết sẵn câu tiếng Việt
  final fieldErrors = <String, String>{};
  for (final x in (body['errors'] as List? ?? [])) {
    fieldErrors['${x['field'] ?? ''}'] = '${x['message'] ?? ''}';
  }
  return ApiException(status, body['errorCode'], body['message'] ?? 'Có lỗi xảy ra.', fieldErrors);
}
