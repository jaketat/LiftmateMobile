// API "Tài khoản của tôi" phần tài xế cần trên điện thoại (theo web AccountPage.tsx):
// giấy tờ của tôi (bằng lái, chứng chỉ vận hành...), thiết bị đang đăng nhập.
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/api/call.dart';
import 'driver_api.dart' show readList, readString, serverDate;

/// Loại giấy tờ của người (giống web lib/compliance.ts PERSON_DOC_TYPES)
const List<String> personDocTypes = <String>[
  'DriverLicense',
  'OperatorCertificate',
  'SafetyCard',
  'NationalId',
  'CompulsoryInsurance',
  'VoluntaryInsurance',
];

class MyDocument {
  final String publicId;
  final String documentType;
  final String? documentNumber;
  final String? issuedBy;
  final DateTime? issuedAt;
  final DateTime effectiveUntil;
  final String? fileUrl;
  final bool isVoided;
  final String? voidReason;

  const MyDocument({
    required this.publicId,
    required this.documentType,
    required this.documentNumber,
    required this.issuedBy,
    required this.issuedAt,
    required this.effectiveUntil,
    required this.fileUrl,
    required this.isVoided,
    required this.voidReason,
  });

  factory MyDocument.fromJson(Map<String, dynamic> json) {
    final String? issued = json['issuedAt'] as String?;
    return MyDocument(
      publicId: readString(json['publicId']),
      documentType: readString(json['documentType']),
      documentNumber: json['documentNumber'] as String?,
      issuedBy: json['issuedBy'] as String?,
      issuedAt: issued == null ? null : DateTime.parse(issued),
      effectiveUntil: DateTime.parse(json['effectiveUntil'] as String),
      fileUrl: json['fileUrl'] as String?,
      isVoided: json['isVoided'] == true,
      voidReason: json['voidReason'] as String?,
    );
  }
}

class LoginSession {
  final String publicId;
  final String? deviceName;
  final String? platform;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final String? ipAddress;
  final bool isCurrent;

  const LoginSession({
    required this.publicId,
    required this.deviceName,
    required this.platform,
    required this.createdAt,
    required this.lastUsedAt,
    required this.ipAddress,
    required this.isCurrent,
  });

  bool get isMobile => RegExp(r'android|ios|iphone|mobile', caseSensitive: false).hasMatch('$platform $deviceName');

  factory LoginSession.fromJson(Map<String, dynamic> json) {
    final String? lastUsed = json['lastUsedAt'] as String?;
    return LoginSession(
      publicId: readString(json['publicId']),
      deviceName: json['deviceName'] as String?,
      platform: json['platform'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastUsedAt: lastUsed == null ? null : DateTime.parse(lastUsed),
      ipAddress: json['ipAddress'] as String?,
      isCurrent: json['isCurrent'] == true,
    );
  }
}

/// Giấy tờ của tôi, mới nhất trước (gồm dòng đã hủy)
Future<List<MyDocument>> fetchMyDocuments(String userId) {
  return call(
    () => dio.get('/Users/$userId/compliance-documents'),
    (dynamic data) => readList(data).map(MyDocument.fromJson).toList(),
  );
}

/// Tải ảnh giấy tờ lên kho tệp, trả fileKey để gắn vào giấy
Future<String> uploadDocumentPhoto(String filePath) async {
  final FormData form = FormData.fromMap(<String, dynamic>{
    'folder': 'staff-documents',
    'file': await MultipartFile.fromFile(filePath, contentType: DioMediaType('image', 'jpeg')),
  });
  return call(
    () => dio.post('/Files/upload', data: form),
    (dynamic data) => readString((data as Map<String, dynamic>)['fileKey']),
  );
}

/// Tự nạp / gia hạn giấy tờ của mình. Nhân sự tự khai bắt buộc kèm ảnh (EVIDENCE_FILE_REQUIRED).
/// Mỗi lần gia hạn là một dòng mới; dòng cũ vẫn giữ để tra lại.
Future<void> recordMyDocument({
  required String documentType,
  required DateTime effectiveUntil,
  required String fileKey,
  String? documentNumber,
  String? issuedBy,
  DateTime? issuedAt,
  required String idempotencyKey,
}) {
  return call(
    () {
      return dio.patch(
        '/Users/me/compliance-documents',
        data: <String, dynamic>{
          'documentType': documentType,
          'documentNumber': (documentNumber ?? '').trim().isEmpty ? null : documentNumber!.trim(),
          'issuedBy': (issuedBy ?? '').trim().isEmpty ? null : issuedBy!.trim(),
          'issuedAt': issuedAt == null ? null : serverDate(issuedAt),
          'effectiveUntil': serverDate(effectiveUntil),
          'fileKeyOrUrl': fileKey,
        },
        options: Options(headers: <String, dynamic>{'Idempotency-Key': idempotencyKey}),
      );
    },
    (dynamic _) => null,
  );
}

String newIdempotencyKey() => const Uuid().v4();

/// Hủy dòng mình nhập sai (không xóa, đánh dấu đã hủy kèm lý do; chỉ hủy được dòng mình khai)
Future<void> voidMyDocument(String userId, String documentId, String reason) {
  return call(
    () => dio.post('/Users/$userId/compliance-documents/$documentId/void', data: <String, dynamic>{'reason': reason}),
    (dynamic _) => null,
  );
}

Future<List<LoginSession>> fetchLoginSessions() {
  return call(
    () => dio.get('/auth/sessions'),
    (dynamic data) => readList(data).map(LoginSession.fromJson).toList(),
  );
}

Future<void> revokeLoginSession(String sessionId) {
  return call(() => dio.delete('/auth/sessions/$sessionId'), (dynamic _) => null);
}

/// Đăng xuất mọi thiết bị, kể cả máy này
Future<void> revokeAllLoginSessions() {
  return call(() => dio.delete('/auth/sessions'), (dynamic _) => null);
}
