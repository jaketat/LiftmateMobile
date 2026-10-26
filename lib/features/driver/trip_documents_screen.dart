// T5: ảnh hiện trường và biên bản giao hàng của một chuyến (BR-DOC-008).
// Theo web (src/features/driver/TripPhotos.tsx):
// - Chụp được khi canUploadDocuments; nén trên máy (cạnh dài 2.560 px, JPEG 85%) trước khi gửi,
//   kèm giờ chụp và vị trí nếu đang chia sẻ. Ảnh đang gửi / gửi lỗi giữ trên máy, bấm để gửi lại.
// - Xem lại ảnh tổ lái đã gửi cho CHÍNH chuyến này, gồm ảnh điều phối đã loại (mờ, kèm lý do).
// - Đường dẫn ảnh có chữ ký hết hạn sau 1 giờ: ảnh lỗi thì tải lại danh sách một lần.
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/call.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/ios.dart';
import 'driver_api.dart';
import 'driver_providers.dart';
import 'driver_widgets.dart' show docCounts;
import 'trip_detail_screen.dart' show currentPositionOrNull;
import 'trip_logic.dart';

const Map<String, String> documentKindLabels = <String, String>{
  'FieldPhoto': 'ảnh hiện trường',
  'POD': 'biên bản giao hàng',
};

class _LocalPhoto {
  final String id;
  final String kind;
  final XFile file;
  bool sending;
  String? error;
  double progress;

  _LocalPhoto({required this.kind, required this.file})
      : id = const Uuid().v4(),
        sending = true,
        progress = 0;
}

class TripDocumentsScreen extends ConsumerStatefulWidget {
  final String tripId;

  const TripDocumentsScreen({super.key, required this.tripId});

  @override
  ConsumerState<TripDocumentsScreen> createState() => _TripDocumentsScreenState();
}

class _TripDocumentsScreenState extends ConsumerState<TripDocumentsScreen> {
  final ImagePicker picker = ImagePicker();
  final List<_LocalPhoto> local = <_LocalPhoto>[];
  bool reloadedForExpiredUrl = false;

  MyTrip? _trip() {
    for (final MyTrip trip in ref.watch(driverTripsProvider).value ?? const <MyTrip>[]) {
      if (trip.publicId == widget.tripId) return trip;
    }
    return null;
  }

  Future<void> capture(String kind, ImageSource source) async {
    final List<XFile> picked;
    if (source == ImageSource.camera) {
      final XFile? one = await picker.pickImage(source: source, maxWidth: 2560, maxHeight: 2560, imageQuality: 85);
      picked = one == null ? <XFile>[] : <XFile>[one];
    } else {
      picked = await picker.pickMultiImage(maxWidth: 2560, maxHeight: 2560, imageQuality: 85);
    }
    if (picked.isEmpty || !mounted) return;
    final List<_LocalPhoto> added = picked.map((XFile file) => _LocalPhoto(kind: kind, file: file)).toList();
    setState(() => local.addAll(added));
    for (final _LocalPhoto photo in added) {
      send(photo);
    }
  }

  Future<void> send(_LocalPhoto photo) async {
    setState(() {
      photo.sending = true;
      photo.error = null;
      photo.progress = 0;
    });
    try {
      final bool sharing = ref.read(consentProvider).value?.accepted ?? false;
      final Position? position = sharing ? await currentPositionOrNull() : null;
      // Giờ chụp: giờ sửa tệp, không vượt giờ hiện tại (server từ chối quá 10 phút ở tương lai)
      DateTime takenAt = await photo.file.lastModified();
      if (takenAt.isAfter(DateTime.now())) takenAt = DateTime.now();
      await uploadTripDocument(
        tripId: widget.tripId,
        filePath: photo.file.path,
        documentType: photo.kind,
        takenAt: takenAt,
        latitude: position?.latitude,
        longitude: position?.longitude,
        onProgress: (int sent, int total) {
          if (total > 0 && mounted) setState(() => photo.progress = sent / total);
        },
      );
      if (!mounted) return;
      // Gửi xong: ảnh chuyển sang danh sách của máy chủ (nguồn đúng), bỏ bản trên máy
      setState(() => local.remove(photo));
      ref.invalidate(tripDocumentsProvider(widget.tripId));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        photo.sending = false;
        photo.error = error.message;
      });
    }
  }

  Future<void> chooseSource(String kind) async {
    final ImageSource? source = await showCupertinoModalPopup<ImageSource>(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: Text(kind == 'POD' ? 'Biên bản giao hàng' : 'Ảnh hiện trường'),
        message: Text(kind == 'POD'
            ? 'Chụp thẳng, đủ sáng, thấy rõ chữ ký và dấu của khách.'
            : 'Chụp hàng đã giao, chỗ đặt hàng và tình trạng xung quanh.'),
        actions: <Widget>[
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, ImageSource.camera),
            child: const Text('Chụp ảnh'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, ImageSource.gallery),
            child: const Text('Chọn từ thư viện'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Thôi'),
        ),
      ),
    );
    if (source != null) await capture(kind, source);
  }

  Future<void> refresh() async {
    reloadedForExpiredUrl = false;
    ref.invalidate(tripDocumentsProvider(widget.tripId));
    await ref.read(tripDocumentsProvider(widget.tripId).future).catchError((Object _) => <TripDocument>[]);
  }

  @override
  Widget build(BuildContext context) {
    final MyTrip? trip = _trip();
    final bool canUpload = trip?.canUploadDocuments ?? false;
    final AsyncValue<List<TripDocument>> docsValue = ref.watch(tripDocumentsProvider(widget.tripId));
    final List<TripDocument> sent = docsValue.value ?? const <TripDocument>[];
    final ({int field, int pod}) counts = docCounts(sent);

    final List<Widget> slivers = <Widget>[];

    if (trip != null) {
      slivers.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Glass(
              opacity: 0.55,
              shadow: false,
              borderRadius: BorderRadius.circular(999),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(
                '${trip.orderCode} · ${tripTimeText(trip, withDay: true)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.navy),
              ),
            ),
          ),
        ),
      ));
    }

    // Danh sách cần nộp: mỗi loại một dòng, dấu tích khi đã có, nút "Chụp" bên phải
    final bool sending = local.any((_LocalPhoto p) => p.sending);
    slivers.add(SliverToBoxAdapter(
      child: IosGroup(
        header: 'Cần nộp khi xong chuyến',
        dividerIndent: 62,
        footer: canUpload
            ? (sending ? 'Đang gửi ảnh… Giữ app mở cho tới khi gửi xong.' : 'Ảnh kèm giờ chụp và vị trí (nếu đang chia sẻ).')
            : 'Chỉ gửi được khi đơn ở bước Đã chốt lịch, Đang thực hiện hoặc Chờ chốt phát sinh.',
        children: <Widget>[
          _NeedRow(
            icon: CupertinoIcons.camera,
            title: 'Ảnh hiện trường',
            count: counts.field,
            onCapture: canUpload ? () => chooseSource('FieldPhoto') : null,
          ),
          _NeedRow(
            icon: CupertinoIcons.doc_text,
            title: 'Biên bản giao hàng',
            count: counts.pod,
            onCapture: canUpload ? () => chooseSource('POD') : null,
          ),
        ],
      ),
    ));

    if (docsValue.isLoading && sent.isEmpty) {
      slivers.add(const SliverToBoxAdapter(
        child: Padding(padding: EdgeInsets.all(24), child: Center(child: CupertinoActivityIndicator(radius: 14))),
      ));
    } else if (docsValue.hasError && sent.isEmpty) {
      final Object error = docsValue.error!;
      final bool closed = error is ApiException && error.code == 'TRIP_DOCUMENTS_CLOSED';
      slivers.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
          child: Text(
            closed ? 'Đơn đã xuất hóa đơn hoặc đã hủy: không xem lại ảnh qua app được nữa.' : errorMessage(error),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: IosColors.secondaryLabel),
          ),
        ),
      ));
    } else {
      for (final String kind in <String>['POD', 'FieldPhoto']) {
        final List<Widget> tiles = <Widget>[
          for (final _LocalPhoto photo in local)
            if (photo.kind == kind) _LocalTile(photo: photo, onRetry: () => send(photo)),
          for (final TripDocument doc in sent)
            if ((doc.documentType == 'POD') == (kind == 'POD'))
              _SentTile(
                doc: doc,
                onExpired: () {
                  if (reloadedForExpiredUrl) return;
                  reloadedForExpiredUrl = true;
                  ref.invalidate(tripDocumentsProvider(widget.tripId));
                },
              ),
        ];
        if (tiles.isEmpty) continue;
        slivers.add(SliverToBoxAdapter(
          child: IosGroup(
            header: kind == 'POD' ? 'Biên bản (${tiles.length})' : 'Ảnh hiện trường (${tiles.length})',
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(8),
                child: GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  children: tiles,
                ),
              ),
            ],
          ),
        ));
      }

      _LocalPhoto? failed;
      for (final _LocalPhoto photo in local) {
        if (photo.error != null) failed = photo;
      }
      final List<String> notes = <String>[
        if (failed != null) '${failed.error} Bấm vào ảnh để gửi lại.',
        if (sent.any((TripDocument d) => d.isVoided)) 'Ảnh mờ là ảnh điều phối đã loại (bấm ảnh để xem lý do). Chụp lại nếu cần.',
      ];
      for (final String note in notes) {
        slivers.add(SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 10),
            child: Text(
              note,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: note == notes.first && failed != null ? IosColors.red : IosColors.secondaryLabel,
              ),
            ),
          ),
        ));
      }
    }

    return IosPage(
      title: 'Ảnh, biên bản',
      glow: IosColors.orange,
      onRefresh: refresh,
      slivers: slivers,
    );
  }
}

/// Một dòng "cần nộp": biểu tượng nét mảnh, tên, đã có mấy ảnh, nút "Chụp" viên thuốc nền nhạt
class _NeedRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;
  final VoidCallback? onCapture;

  const _NeedRow({required this.icon, required this.title, required this.count, required this.onCapture});

  @override
  Widget build(BuildContext context) {
    final bool ok = count > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (ok ? IosColors.green : IosColors.orange).withValues(alpha: 0.13),
            ),
            alignment: Alignment.center,
            child: Icon(
              ok ? CupertinoIcons.checkmark_alt : icon,
              size: 18,
              color: ok ? AppColors.okText : const Color(0xFFB4541A),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: const TextStyle(fontSize: 17, color: AppColors.text)),
                Text(
                  ok ? 'Đã gửi $count ảnh' : 'Chưa có',
                  style: TextStyle(fontSize: 14, color: ok ? IosColors.secondaryLabel : const Color(0xFFB4541A)),
                ),
              ],
            ),
          ),
          if (onCapture != null)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(44, 34),
              color: AppColors.navy.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
              onPressed: onCapture,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(CupertinoIcons.camera_fill, size: 16, color: AppColors.navy),
                  const SizedBox(width: 6),
                  Text(ok ? 'Thêm' : 'Chụp',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.navy)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LocalTile extends StatelessWidget {
  final _LocalPhoto photo;
  final VoidCallback onRetry;

  const _LocalTile({required this.photo, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${documentKindLabels[photo.kind]} vừa chụp, ${photo.sending ? 'đang gửi' : 'gửi lỗi, bấm để gửi lại'}',
      button: !photo.sending,
      child: GestureDetector(
        onTap: photo.sending ? null : onRetry,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Image.file(File(photo.file.path), fit: BoxFit.cover),
              Container(color: Colors.black.withValues(alpha: photo.sending ? 0.30 : 0.45)),
              if (photo.sending) ...<Widget>[
                const Center(child: CupertinoActivityIndicator(color: Colors.white, radius: 11)),
                // Thanh tiến độ mảnh ở đáy ô
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: SizedBox(
                      height: 3,
                      child: Stack(
                        children: <Widget>[
                          Container(color: Colors.white.withValues(alpha: 0.35)),
                          FractionallySizedBox(
                            widthFactor: photo.progress.clamp(0.0, 1.0),
                            child: Container(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ] else
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(CupertinoIcons.arrow_clockwise, color: Colors.white, size: 22),
                      SizedBox(height: 2),
                      Text('Gửi lại', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SentTile extends StatelessWidget {
  final TripDocument doc;
  final VoidCallback onExpired;

  const _SentTile({required this.doc, required this.onExpired});

  /// Xem ảnh toàn màn hình nền đen như app Ảnh: phóng to bằng hai ngón, thông tin ở đáy
  void showInfo(BuildContext context) {
    final String who = '${documentKindLabels[doc.documentType] ?? doc.documentTypeName} · ${clock(doc.receivedAt)}'
        '${doc.uploadedByName.isNotEmpty ? ' · ${doc.uploadedByName}' : ''}';
    Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (BuildContext context, Animation<double> a, Animation<double> b) => FadeTransition(
        opacity: a,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: <Widget>[
              Positioned.fill(
                child: InteractiveViewer(
                  maxScale: 5,
                  child: Center(child: Image.network(doc.fileUrl, fit: BoxFit.contain)),
                ),
              ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 8,
                left: 12,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  onPressed: () => Navigator.of(context).pop(),
                  child: ClipOval(
                    child: Container(
                      width: 36,
                      height: 36,
                      color: Colors.white.withValues(alpha: 0.18),
                      child: const Icon(CupertinoIcons.xmark, color: Colors.white, size: 18, semanticLabel: 'Đóng'),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: MediaQuery.paddingOf(context).bottom + 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(who, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                    if (doc.isVoided)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Đã bị loại${doc.voidReason == null ? '' : ': ${doc.voidReason}'}',
                          style: const TextStyle(color: Color(0xFFFF6961), fontSize: 14),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${documentKindLabels[doc.documentType] ?? doc.documentTypeName} lúc ${clock(doc.receivedAt)}'
          '${doc.isVoided ? ', đã bị loại' : ''}',
      child: GestureDetector(
        onTap: () => showInfo(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Opacity(
                opacity: doc.isVoided ? 0.3 : 1,
                child: Image.network(
                  doc.fileUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
                    WidgetsBinding.instance.addPostFrameCallback((_) => onExpired());
                    return Container(
                      color: const Color(0xFFE5E5EA),
                      child: const Icon(CupertinoIcons.photo, color: IosColors.secondaryLabel),
                    );
                  },
                ),
              ),
              // Giờ gửi trên dải tối mờ ở đáy, như ô video trong app Ảnh
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(6, 10, 6, 4),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[Color(0x00000000), Color(0x8C000000)],
                    ),
                  ),
                  child: Text(
                    clock(doc.receivedAt),
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              if (doc.isVoided)
                Positioned(
                  top: 5,
                  left: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: IosColors.red, borderRadius: BorderRadius.circular(999)),
                    child: const Text('Đã loại',
                        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
