// Q1: xử lý một báo hồng - xem tiến độ, bấm "Đã nhận", hoặc "Đóng báo".
// Đóng báo xong thì xe gán chuyến lại được.
import 'package:flutter/cupertino.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/labels.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../auth/session_provider.dart';
import 'maintenance_api.dart';
import 'maintenance_providers.dart';
import 'breakdown_list_screen.dart' show breakdownStatusColor;
import '../../core/widgets/ios.dart';

const int minNoteLength = 10;
const int maxNoteLength = 500;

class BreakdownDetailScreen extends ConsumerStatefulWidget {
  final String reportId;

  BreakdownDetailScreen({super.key, required this.reportId});

  @override
  ConsumerState<BreakdownDetailScreen> createState() => _BreakdownDetailScreenState();
}

class _BreakdownDetailScreenState extends ConsumerState<BreakdownDetailScreen> {
  final TextEditingController noteController = TextEditingController();
  // Lịch sửa chữa liên quan, không bắt buộc
  String? linkedRecordId;

  bool isSaving = false;
  String? errorText;

  @override
  void dispose() {
    noteController.dispose();
    super.dispose();
  }

  /// "Đã nhận": báo cho tài xế biết đã có người lo.
  Future<void> acknowledge(BreakdownReport report) async {
    setState(() {
      isSaving = true;
      errorText = null;
    });
    try {
      await acknowledgeBreakdown(report.publicId);
      ref.invalidate(breakdownProvider(report.publicId));
      ref.invalidate(breakdownsPageProvider);
      ref.invalidate(openBreakdownCountProvider);
      if (!mounted) {
        return;
      }
      // Nhận xong vẫn ở lại màn để đóng báo: mở khóa nút
      setState(() {
        isSaving = false;
      });
      showIosToast(context, t('maintenance.breakdownDetail.acknowledged'));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        isSaving = false;
        errorText = errorMessage(error);
      });
    }
  }

  Future<void> resolve(BreakdownReport report) async {
    final String note = noteController.text.trim();
    if (note.length < minNoteLength) {
      setState(() {
        errorText = t('maintenance.breakdownDetail.noteTooShort', <String, Object?>{'min': minNoteLength});
      });
      return;
    }
    setState(() {
      isSaving = true;
      errorText = null;
    });
    try {
      await resolveBreakdown(report.publicId, note, linkedRecordId);
      ref.invalidate(breakdownProvider(report.publicId));
      ref.invalidate(breakdownsPageProvider);
      ref.invalidate(openBreakdownCountProvider);
      ref.invalidate(myBreakdownsProvider);
      if (!mounted) {
        return;
      }
      setState(() {
        isSaving = false;
      });
      showIosToast(context, t('maintenance.breakdownDetail.closed'));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        isSaving = false;
        errorText = errorMessage(error);
      });
    }
  }

  // Chọn lịch sửa chữa liên quan từ bảng chọn iOS, có dòng "Không liên kết"
  Future<void> pickRecord(List<MaintenanceRecord> records) async {
    final String? picked = await showIosActionSheet<String>(
      context,
      title: t('maintenance.breakdownDetail.chooseRecord'),
      options: <IosSheetOption<String>>[
        IosSheetOption<String>('', t('maintenance.breakdownDetail.noLink')),
        for (final MaintenanceRecord record in records)
          IosSheetOption<String>(record.publicId, '${record.title} · ${formatDate(record.completedOn.isEmpty ? record.startDate : record.completedOn)}'),
      ],
    );
    if (picked != null && mounted) setState(() => linkedRecordId = picked.isEmpty ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final String reportId = widget.reportId;
    final AsyncValue<BreakdownReport> reportValue = ref.watch(breakdownProvider(reportId));
    final BreakdownReport? report = reportValue.value;
    if (report == null) {
      return IosPage(
        title: t('maintenance.breakdownList.title'),
        slivers: <Widget>[
          SliverFillRemaining(
            hasScrollBody: false,
            child: AsyncView<BreakdownReport>(
              value: reportValue,
              onRetry: () => ref.invalidate(breakdownProvider(reportId)),
              builder: (BreakdownReport _) => const SizedBox.shrink(),
            ),
          ),
        ],
      );
    }
    return IosPage(
      title: t('maintenance.breakdownDetail.title', <String, Object?>{'vehicle': report.vehicleLabel}).trim(),
      onRefresh: () => ref.refresh(breakdownProvider(reportId).future),
      slivers: <Widget>[SliverToBoxAdapter(child: buildBody(report))],
    );
  }

  Widget progressRow(String text, bool isDone) {
    return IosRow(
      leading: Icon(
        isDone ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
        size: 26,
        color: isDone ? IosColors.green : IosColors.tertiaryLabel,
      ),
      titleWidget: Text(
        text,
        style: TextStyle(fontSize: 15, height: 1.35, color: isDone ? AppColors.text : IosColors.secondaryLabel),
      ),
      title: text,
      chevron: false,
    );
  }

  Widget buildBody(BreakdownReport report) {
    final Session? session = ref.watch(sessionProvider).value;
    final bool canManage = session != null && session.can('Orders.Dispatch');
    final bool mustStop = report.severity == 'MustStop';
    final bool isResolved = report.status == 'Resolved';

    final List<Widget> children = <Widget>[
      // Mô tả + ảnh + ai gửi
      IosGroup(
        footer: '${report.reportedByName} · ${formatDateTime(report.reportedAt)} · ${report.orderCode}',
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    IosPill(label(breakdownSeverityLabels, report.severity), color: mustStop ? IosColors.red : IosColors.orange),
                    IosPill(label(breakdownStatusLabels, report.status), color: breakdownStatusColor(report.status)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(report.description, style: TextStyle(fontSize: 17, height: 1.4, color: AppColors.text)),
                if (report.photoUrls.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 88,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: report.photoUrls.length,
                      separatorBuilder: (BuildContext context, int index) => const SizedBox(width: 10),
                      itemBuilder: (BuildContext context, int index) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.network(
                            report.photoUrls[index],
                            width: 88,
                            height: 88,
                            fit: BoxFit.cover,
                            // Ảnh hỏng thì chỉ ô trống, không văng app
                            errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
                              return Container(
                                width: 88,
                                height: 88,
                                color: IosColors.fill,
                                child: Icon(CupertinoIcons.photo, color: IosColors.secondaryLabel),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      IosGroup(
        header: t('breakdowns.progress'),
        headerIcon: CupertinoIcons.list_bullet,
        dividerIndent: 58,
        footer: !isResolved && canManage
            ? (report.status == 'Open' ? t('maintenance.breakdownDetail.ackHint') : t('maintenance.breakdownDetail.alreadyAcked'))
            : null,
        children: <Widget>[
          progressRow(t('maintenance.breakdownDetail.sentBy', <String, Object?>{'time': _timeOf(report.reportedAt), 'name': report.reportedByName}), true),
          progressRow(
            report.acknowledgedAt.isEmpty
                ? t('maintenance.breakdownDetail.waitingAck')
                : t('maintenance.breakdownDetail.ackBy', <String, Object?>{'time': _timeOf(report.acknowledgedAt), 'name': report.acknowledgedByName}),
            report.acknowledgedAt.isNotEmpty,
          ),
          progressRow(
            isResolved
                ? t('maintenance.breakdownDetail.closedBy', <String, Object?>{'time': _timeOf(report.resolvedAt), 'name': report.resolvedByName})
                : t('maintenance.breakdownDetail.waitingClose'),
            isResolved,
          ),
          // Còn "Mới" thì cho bấm "Đã nhận" ngay ở đây
          if (!isResolved && canManage && report.status == 'Open')
            IosRow(
              title: t('maintenance.breakdownDetail.acknowledge'),
              centered: true,
              titleWidget: Text(
                t('maintenance.breakdownDetail.acknowledge'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: IosColors.blue),
              ),
              onTap: isSaving ? null : () => acknowledge(report),
            ),
        ],
      ),
    ];

    if (isResolved) {
      // Đã đóng rồi: chỉ xem kết quả, không sửa được nữa
      children.add(IosGroup(
        header: t('maintenance.breakdownDetail.resolvedHeading'),
        headerIcon: CupertinoIcons.checkmark_seal_fill,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              report.resolutionNote.isEmpty ? t('maintenance.breakdownDetail.noNote') : report.resolutionNote,
              style: TextStyle(fontSize: 16, height: 1.45, color: AppColors.text),
            ),
          ),
        ],
      ));
    } else if (canManage) {
      final AsyncValue<List<MaintenanceRecord>> recordsValue = ref.watch(vehicleMaintenanceProvider(report.vehiclePublicId));
      final List<MaintenanceRecord>? records = recordsValue.value;
      String? linkedTitle;
      for (final MaintenanceRecord record in records ?? <MaintenanceRecord>[]) {
        if (record.publicId == linkedRecordId) linkedTitle = record.title;
      }
      children.add(IosGroup(
        header: t('maintenance.breakdownDetail.closeHeading'),
        headerIcon: CupertinoIcons.wrench_fill,
        footer: t('maintenance.breakdownDetail.noteCount', <String, Object?>{
          'count': noteController.text.length,
          'max': maxNoteLength,
          'min': minNoteLength,
        }),
        children: <Widget>[
          IosTextArea(
            controller: noteController,
            placeholder: '${t('maintenance.breakdownDetail.howHandled')}. ${t('maintenance.breakdownDetail.notePlaceholder')}',
            enabled: !isSaving,
            minLines: 3,
            maxLines: 6,
            maxLength: maxNoteLength,
            onChanged: (String _) => setState(() {}),
          ),
          if (recordsValue.hasError && !recordsValue.isLoading)
            IosRow(
              icon: CupertinoIcons.exclamationmark_circle,
              iconColor: IosColors.red,
              title: errorMessage(recordsValue.error!),
              subtitle: t('common.retry'),
              onTap: () => ref.invalidate(vehicleMaintenanceProvider(report.vehiclePublicId)),
            )
          else
            IosRow(
              title: t('maintenance.breakdownDetail.linkedRecord'),
              subtitle: linkedTitle ?? t('maintenance.breakdownDetail.optionalHint'),
              trailing: records == null ? const CupertinoActivityIndicator() : null,
              onTap: records == null || isSaving ? null : () => pickRecord(records),
            ),
        ],
      ));
      if (errorText != null) children.add(IosErrorText(errorText!));
      children.add(IosFormButton(
        label: isSaving ? t('maintenance.breakdownDetail.saving') : t('maintenance.breakdownDetail.closeAction'),
        icon: CupertinoIcons.checkmark_alt,
        busy: isSaving,
        onPressed: () => resolve(report),
      ));
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
        child: Text(t('maintenance.breakdownDetail.closeNote'), style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel)),
      ));
    }

    return Column(children: children);
  }
}

String _timeOf(String isoText) {
  if (isoText.isEmpty) {
    return '';
  }
  final DateTime moment = DateTime.parse(isoText).toLocal();
  return '${moment.hour.toString().padLeft(2, '0')}:${moment.minute.toString().padLeft(2, '0')}';
}