// "Giấy tờ của tôi" kiểu iOS (Cupertino + Liquid Glass): tài xế tự xem và gia hạn bằng lái,
// chứng chỉ vận hành, thẻ an toàn...
// Theo web (StaffDocs.tsx MyDocs + ComplianceDocs.tsx): mỗi loại một nhóm, dòng hiệu lực trên cùng,
// dòng cũ ghi "Bản cũ", dòng đã hủy mờ kèm lý do. Tự khai bắt buộc chụp ảnh giấy.
// Giấy tờ nhân sự chỉ nhắc, không chặn: quá hạn màu vàng; ≤3 ngày "Gấp"; ≤7 ngày nhắc.
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/call.dart';
import '../../core/labels.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/ios.dart';
import '../auth/session_provider.dart';
import 'account_api.dart';

final myDocumentsProvider = FutureProvider.autoDispose.family<List<MyDocument>, String>((Ref ref, String userId) {
  return fetchMyDocuments(userId);
});

String _two(int v) => v.toString().padLeft(2, '0');
String _day(DateTime d) {
  final DateTime l = d.toLocal();
  return '${_two(l.day)}/${_two(l.month)}/${l.year}';
}

/// Nhãn và màu hạn giấy (giống web docState, giấy người không bao giờ chặn)
({String text, Color color}) documentState(MyDocument doc, DateTime now) {
  if (doc.isVoided) {
    return (text: 'Đã hủy', color: const Color(0xFF8E8E93));
  }
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime until = doc.effectiveUntil.toLocal();
  final int days = DateTime(until.year, until.month, until.day).difference(today).inDays;
  if (days < 0) return (text: 'Quá hạn ${-days} ngày', color: IosColors.orange);
  if (days == 0) return (text: 'Hết hạn hôm nay', color: IosColors.orange);
  if (days <= 3) return (text: 'Gấp · còn $days ngày', color: IosColors.orange);
  if (days <= 7) return (text: 'Còn $days ngày', color: IosColors.orange);
  return (text: 'Còn hạn đến ${_day(doc.effectiveUntil)}', color: IosColors.green);
}

class MyDocumentsScreen extends ConsumerWidget {
  const MyDocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Session? session = ref.watch(sessionProvider).value;
    final String userId = session?.userId ?? '';
    if (userId.isEmpty) {
      return const IosPage(
        title: 'Giấy tờ',
        slivers: <Widget>[SliverToBoxAdapter(child: EmptyView(text: 'Chưa đọc được tài khoản.'))],
      );
    }
    final AsyncValue<List<MyDocument>> value = ref.watch(myDocumentsProvider(userId));

    Future<void> openForm(String? type) async {
      final bool? saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.25),
        builder: (BuildContext context) => _RecordForm(initialType: type),
      );
      if (saved == true) {
        ref.invalidate(myDocumentsProvider(userId));
      }
    }

    final List<Widget> slivers = value.when(
      data: (List<MyDocument> docs) {
        if (docs.isEmpty) {
          return <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(40, 24, 40, 0),
                child: Column(
                  children: <Widget>[
                    const Icon(CupertinoIcons.doc_text, size: 56, color: IosColors.tertiaryLabel),
                    const SizedBox(height: 12),
                    const Text('Chưa có giấy tờ',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text)),
                    const SizedBox(height: 6),
                    const Text(
                      'Nạp bằng lái, chứng chỉ để hệ thống nhắc trước khi hết hạn.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: IosColors.secondaryLabel, height: 1.4),
                    ),
                    const SizedBox(height: 20),
                    IosPillButton(label: 'Nạp giấy tờ', icon: CupertinoIcons.plus, onPressed: () => openForm(null)),
                  ],
                ),
              ),
            ),
          ];
        }
        final List<String> types = <String>[];
        for (final MyDocument doc in docs) {
          if (!types.contains(doc.documentType)) types.add(doc.documentType);
        }
        return <Widget>[
          for (final String type in types)
            SliverToBoxAdapter(
              child: _DocGroup(
                type: type,
                rows: docs.where((MyDocument d) => d.documentType == type).toList(),
                userId: userId,
                onRenew: () => openForm(type),
                onChanged: () => ref.invalidate(myDocumentsProvider(userId)),
              ),
            ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(32, 0, 32, 8),
              child: Text(
                'Mỗi lần gia hạn là một dòng mới; dòng cũ vẫn giữ để tra lại. Bấm một dòng để xem ảnh hoặc hủy dòng nhập sai.',
                style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel, height: 1.35),
              ),
            ),
          ),
        ];
      },
      loading: () => const <Widget>[
        SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(top: 60), child: CupertinoActivityIndicator(radius: 13))),
      ],
      error: (Object error, StackTrace _) => <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 40, 32, 0),
            child: Column(
              children: <Widget>[
                Text(errorMessage(error),
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: IosColors.secondaryLabel)),
                CupertinoButton(onPressed: () => ref.invalidate(myDocumentsProvider(userId)), child: const Text('Thử lại')),
              ],
            ),
          ),
        ),
      ],
    );

    return IosPage(
      title: 'Giấy tờ',
      trailing: IosGlassIconButton(icon: CupertinoIcons.add, tooltip: 'Nạp giấy tờ', onPressed: () => openForm(null)),
      onRefresh: () => ref.refresh(myDocumentsProvider(userId).future),
      slivers: slivers,
    );
  }
}

class _DocGroup extends StatelessWidget {
  final String type;
  final List<MyDocument> rows;
  final String userId;
  final VoidCallback onRenew;
  final VoidCallback onChanged;

  const _DocGroup({required this.type, required this.rows, required this.userId, required this.onRenew, required this.onChanged});

  Future<void> openActions(BuildContext context, MyDocument doc) async {
    final bool hasPhoto = (doc.fileUrl ?? '').isNotEmpty;
    if (!hasPhoto && doc.isVoided) return;
    final String? choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: Text('${label(personDocumentLabels, doc.documentType)} · hạn ${_day(doc.effectiveUntil)}'),
        actions: <Widget>[
          if (hasPhoto)
            CupertinoActionSheetAction(onPressed: () => Navigator.of(context).pop('photo'), child: const Text('Xem ảnh')),
          if (!doc.isVoided)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(context).pop('void'),
              child: const Text('Hủy dòng nhập sai'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Thôi'),
        ),
      ),
    );
    if (!context.mounted) return;
    if (choice == 'photo') {
      await launchUrl(Uri.parse(doc.fileUrl!), mode: LaunchMode.externalApplication);
    } else if (choice == 'void') {
      await askVoid(context, doc);
    }
  }

  Future<void> askVoid(BuildContext context, MyDocument doc) async {
    final TextEditingController reason = TextEditingController();
    final bool? ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => CupertinoAlertDialog(
          title: const Text('Hủy dòng nhập sai?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.only(top: 4, bottom: 10),
                child: Text('Dòng này không bị xóa mà được đánh dấu đã hủy, kèm lý do, để còn tra lại.'),
              ),
              CupertinoTextField(
                controller: reason,
                autofocus: true,
                placeholder: 'Lý do, VD: gõ nhầm năm hết hạn',
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          actions: <Widget>[
            CupertinoDialogAction(onPressed: () => Navigator.pop(context, false), child: const Text('Thôi')),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: reason.text.trim().length < 5 ? null : () => Navigator.pop(context, true),
              child: const Text('Hủy dòng'),
            ),
          ],
        ),
      ),
    );
    final String text = reason.text.trim();
    reason.dispose();
    if (ok != true) return;
    try {
      await voidMyDocument(userId, doc.publicId, text);
      onChanged();
    } catch (error) {
      if (context.mounted) showErrorSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    MyDocument? current;
    for (final MyDocument doc in rows) {
      if (!doc.isVoided) {
        current = doc;
        break;
      }
    }
    final DateTime now = DateTime.now();
    final ({String text, Color color})? state = current == null ? null : documentState(current, now);
    final Color tint = state?.color ?? const Color(0xFF8E8E93);

    final List<Widget> children = <Widget>[
      // Dòng tóm tắt: hạn của bản hiện hành + nút Gia hạn
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: <Widget>[
            IosIconBadge(
              icon: state == null || tint == IosColors.green
                  ? CupertinoIcons.checkmark_seal_fill
                  : CupertinoIcons.exclamationmark_triangle_fill,
              color: tint,
              size: 36,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    state?.text ?? 'Không còn dòng hiệu lực',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: state == null ? AppColors.text : tint),
                  ),
                  if (current != null && (current.documentNumber ?? '').isNotEmpty)
                    Text('Số ${current.documentNumber}',
                        style: const TextStyle(fontSize: 14, color: IosColors.secondaryLabel)),
                ],
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(44, 34),
              color: IosColors.blue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              onPressed: onRenew,
              child: const Text('Gia hạn', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: IosColors.blue)),
            ),
          ],
        ),
      ),
    ];

    for (final MyDocument doc in rows) {
      final List<String> parts = <String>[
        if ((doc.issuedBy ?? '').isNotEmpty) doc.issuedBy!,
        if (doc.issuedAt != null) 'cấp ${_day(doc.issuedAt!)}',
        if ((doc.fileUrl ?? '').isNotEmpty) 'có ảnh',
      ];
      final String tag = doc.isVoided ? 'Đã hủy' : (doc == current ? 'Hiện hành' : 'Bản cũ');
      children.add(Opacity(
        opacity: doc.isVoided ? 0.55 : 1,
        child: Material(
          color: Colors.white,
          child: InkWell(
            highlightColor: IosColors.fill,
            splashFactory: NoSplash.splashFactory,
            onTap: () => openActions(context, doc),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Hạn ${_day(doc.effectiveUntil)}',
                          style: TextStyle(
                            fontSize: 16,
                            color: AppColors.text,
                            decoration: doc.isVoided ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        if (parts.isNotEmpty)
                          Text(parts.join(' · '), style: const TextStyle(fontSize: 13, color: IosColors.secondaryLabel)),
                        if (doc.isVoided && doc.voidReason != null)
                          Text('Lý do hủy: ${doc.voidReason}',
                              style: const TextStyle(fontSize: 13, color: IosColors.secondaryLabel)),
                      ],
                    ),
                  ),
                  Text(tag, style: const TextStyle(fontSize: 15, color: IosColors.secondaryLabel)),
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(CupertinoIcons.chevron_forward, size: 16, color: IosColors.tertiaryLabel),
                  ),
                ],
              ),
            ),
          ),
        ),
      ));
    }

    return IosGroup(header: label(personDocumentLabels, type), children: children);
  }
}

/// Bảng kính kéo lên để nạp / gia hạn giấy tờ, ô nhập kiểu iOS, chọn ngày bằng bánh xe Cupertino
class _RecordForm extends ConsumerStatefulWidget {
  final String? initialType;

  const _RecordForm({required this.initialType});

  @override
  ConsumerState<_RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends ConsumerState<_RecordForm> {
  late String? type = widget.initialType;
  DateTime? until;
  DateTime? issuedAt;
  final TextEditingController number = TextEditingController();
  final TextEditingController issuedBy = TextEditingController();
  XFile? photo;
  bool busy = false;
  String? error;
  // Sinh một lần khi mở form: mạng yếu bấm lại không tạo hai dòng
  final String idempotencyKey = newIdempotencyKey();

  @override
  void dispose() {
    number.dispose();
    issuedBy.dispose();
    super.dispose();
  }

  String? get missing {
    if (type == null) return 'chọn loại giấy tờ';
    if (until == null) return 'nhập ngày hết hạn';
    if (photo == null) return 'chụp ảnh giấy tờ';
    return null;
  }

  Future<void> pickType() async {
    final String? picked = await showCupertinoModalPopup<String>(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: const Text('Loại giấy tờ'),
        actions: <Widget>[
          for (final String t in personDocTypes)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(context).pop(t),
              child: Text(label(personDocumentLabels, t)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Thôi'),
        ),
      ),
    );
    if (picked != null) setState(() => type = picked);
  }

  Future<void> pickDate(bool forUntil) async {
    final DateTime now = DateTime.now();
    DateTime chosen = (forUntil ? until : issuedAt) ?? DateTime(now.year, now.month, now.day);
    final bool? ok = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (BuildContext context) => Container(
        height: 320,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  CupertinoButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Thôi')),
                  Expanded(
                    child: Text(
                      forUntil ? 'Hết hạn ngày' : 'Ngày cấp',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text),
                    ),
                  ),
                  CupertinoButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Xong', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  dateOrder: DatePickerDateOrder.dmy,
                  initialDateTime: chosen,
                  minimumYear: now.year - 30,
                  maximumYear: now.year + 30,
                  onDateTimeChanged: (DateTime value) => chosen = value,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    setState(() {
      if (forUntil) {
        until = chosen;
      } else {
        issuedAt = chosen;
      }
    });
  }

  Future<void> choosePhoto() async {
    final ImageSource? source = await showCupertinoModalPopup<ImageSource>(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: const Text('Ảnh giấy tờ'),
        actions: <Widget>[
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(ImageSource.camera),
            child: const Text('Chụp ảnh'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(ImageSource.gallery),
            child: const Text('Chọn từ thư viện'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Thôi'),
        ),
      ),
    );
    if (source == null) return;
    final XFile? picked = await ImagePicker().pickImage(source: source, maxWidth: 2560, maxHeight: 2560, imageQuality: 85);
    if (picked != null && mounted) setState(() => photo = picked);
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final String fileKey = await uploadDocumentPhoto(photo!.path);
      await recordMyDocument(
        documentType: type!,
        effectiveUntil: until!,
        fileKey: fileKey,
        documentNumber: number.text,
        issuedBy: issuedBy.text,
        issuedAt: issuedAt,
        idempotencyKey: idempotencyKey,
      );
      if (!mounted) return;
      showIosToast(context, 'Đã nạp ${label(personDocumentLabels, type).toLowerCase()}');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _field(TextEditingController controller, String placeholder) {
    return CupertinoTextField(
      controller: controller,
      enabled: !busy,
      placeholder: placeholder,
      placeholderStyle: const TextStyle(fontSize: 17, color: IosColors.tertiaryLabel),
      style: const TextStyle(fontSize: 17, color: AppColors.text),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final bool pastDate = until != null && until!.isBefore(DateTime(now.year, now.month, now.day));
    final String title =
        widget.initialType == null ? 'Nạp giấy tờ' : 'Gia hạn ${label(personDocumentLabels, widget.initialType).toLowerCase()}';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Glass(
        opacity: 0.88,
        blur: 30,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
        child: ColoredBox(
          color: IosColors.groupedBackground.withValues(alpha: 0.6),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 24),
            children: <Widget>[
              const SheetGrabber(),
              // Thanh trên của bảng: Thôi · tiêu đề · Lưu
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Row(
                  children: <Widget>[
                    CupertinoButton(
                      onPressed: busy ? null : () => Navigator.pop(context, false),
                      child: const Text('Thôi'),
                    ),
                    Expanded(
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text),
                      ),
                    ),
                    CupertinoButton(
                      onPressed: busy || missing != null ? null : save,
                      child: busy
                          ? const CupertinoActivityIndicator()
                          : const Text('Lưu', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
              IosGroup(
                footer: pastDate ? 'Ngày đã qua: giấy này sẽ hiện là quá hạn ngay.' : null,
                children: <Widget>[
                  IosRow(
                    title: 'Loại giấy tờ',
                    value: type == null ? 'Chọn' : label(personDocumentLabels, type),
                    onTap: busy || widget.initialType != null ? null : pickType,
                  ),
                  IosRow(
                    title: 'Hết hạn ngày',
                    value: until == null ? 'Chọn' : _day(until!),
                    onTap: busy ? null : () => pickDate(true),
                  ),
                  IosRow(
                    title: 'Ngày cấp',
                    value: issuedAt == null ? 'Không bắt buộc' : _day(issuedAt!),
                    onTap: busy ? null : () => pickDate(false),
                  ),
                ],
              ),
              IosGroup(
                header: 'Thông tin thêm (không bắt buộc)',
                children: <Widget>[
                  _field(number, 'Số giấy'),
                  _field(issuedBy, 'Nơi cấp'),
                ],
              ),
              IosGroup(
                header: 'Ảnh giấy tờ (bắt buộc)',
                footer: 'Mỗi lần gia hạn là một dòng mới; dòng cũ vẫn giữ để tra lại.',
                children: <Widget>[
                  if (photo != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(File(photo!.path), height: 160, width: double.infinity, fit: BoxFit.cover),
                      ),
                    ),
                  IosRow(
                    icon: CupertinoIcons.camera_fill,
                    iconColor: IosColors.blue,
                    title: photo == null ? 'Thêm ảnh' : 'Đổi ảnh',
                    onTap: busy ? null : choosePhoto,
                  ),
                ],
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 12),
                  child: Text(error!, style: const TextStyle(fontSize: 14, color: IosColors.red)),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: <Widget>[
                    if (missing != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text('Còn thiếu: $missing',
                            style: const TextStyle(fontSize: 14, color: IosColors.secondaryLabel)),
                      ),
                    IosPillButton(
                      label: busy ? 'Đang lưu...' : 'Lưu giấy tờ',
                      busy: busy,
                      onPressed: missing == null ? save : null,
                    ),
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
