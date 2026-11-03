// Q1: xử lý một báo hồng - xem tiến độ, bấm "Đã nhận", hoặc "Đóng báo".
// Đóng báo xong thì xe gán chuyến lại được.
import 'package:flutter/material.dart';
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
import 'widgets.dart';
import '../../core/widgets/ios.dart';
import '../../core/widgets/page_transition.dart';

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

  @override
  Widget build(BuildContext context) {
    final String reportId = widget.reportId;
    final AsyncValue<BreakdownReport> reportValue = ref.watch(breakdownProvider(reportId));

    return Scaffold(
      appBar: AppBar(
        title: Text(t('maintenance.breakdownDetail.title', <String, Object?>{'vehicle': reportValue.value?.vehicleLabel ?? ''}).trim()),
      ),
      body: AsyncView<BreakdownReport>(
        value: reportValue,
        onRetry: () {
          ref.invalidate(breakdownProvider(reportId));
        },
        builder: (BreakdownReport report) {
          return buildBody(report);
        },
      ),
    );
  }

  Widget buildBody(BreakdownReport report) {
    final Session? session = ref.watch(sessionProvider).value;
    final bool canManage = session != null && session.can('Orders.Dispatch');
    final bool mustStop = report.severity == 'MustStop';
    final bool isResolved = report.status == 'Resolved';

    final List<Widget> children = <Widget>[
      // Mô tả + ảnh + ai gửi
      SectionCard(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  report.description,
                  style: TextStyle(fontSize: 15, height: 1.4, color: AppColors.text),
                ),
              ),
              const SizedBox(width: 10),
              ToneChip(
                label(breakdownSeverityLabels, report.severity),
                tone: mustStop ? Tone.danger : Tone.warn,
              ),
            ],
          ),
          if (report.photoUrls.isNotEmpty) ...[
            SizedBox(height: 12),
            SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: report.photoUrls.length,
                separatorBuilder: (BuildContext context, int index) {
                  return const SizedBox(width: 10);
                },
                itemBuilder: (BuildContext context, int index) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      report.photoUrls[index],
                      width: 76,
                      height: 76,
                      fit: BoxFit.cover,
                      // Ảnh hỏng thì chỉ ô trống, không văng app
                      errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
                        return Container(
                          width: 76,
                          height: 76,
                          color: AppColors.navyLight,
                          child: Icon(Icons.image_not_supported_outlined, color: AppColors.textMuted),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
          SizedBox(height: 12),
          Text(
            '${report.reportedByName} · ${formatDateTime(report.reportedAt)} · ${report.orderCode}',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ],
      ),
      SizedBox(height: 20),

      SectionHeading(t('breakdowns.progress')),
      SizedBox(height: 10),
      SectionCard(
        children: <Widget>[
          TimelineRow(
            title: t('maintenance.breakdownDetail.sentBy', <String, Object?>{'time': _timeOf(report.reportedAt), 'name': report.reportedByName}),
            isDone: true,
          ),
          SizedBox(height: 8),
          TimelineRow(
            title: report.acknowledgedAt.isEmpty
                ? t('maintenance.breakdownDetail.waitingAck')
                : t('maintenance.breakdownDetail.ackBy', <String, Object?>{'time': _timeOf(report.acknowledgedAt), 'name': report.acknowledgedByName}),
            isDone: report.acknowledgedAt.isNotEmpty,
          ),
          SizedBox(height: 8),
          TimelineRow(
            title: isResolved
                ? t('maintenance.breakdownDetail.closedBy', <String, Object?>{'time': _timeOf(report.resolvedAt), 'name': report.resolvedByName})
                : t('maintenance.breakdownDetail.waitingClose'),
            isDone: isResolved,
          ),
          // Còn "Mới" thì cho bấm "Đã nhận" ngay ở đây
          if (!isResolved && canManage) ...[
            SizedBox(height: 14),
            if (report.status == 'Open')
              OutlinedButton(
                onPressed: isSaving ? null : () => acknowledge(report),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(t('maintenance.breakdownDetail.acknowledge')),
              )
            else
              NoteText(t('maintenance.breakdownDetail.alreadyAcked')),
            SizedBox(height: 8),
            NoteText(t('maintenance.breakdownDetail.ackHint')),
          ],
        ],
      ),
      SizedBox(height: 20),
    ];

    if (isResolved) {
      // Đã đóng rồi: chỉ xem kết quả, không sửa được nữa
      children.add(SectionHeading(t('maintenance.breakdownDetail.resolvedHeading')));
      children.add(SizedBox(height: 10));
      children.add(
        SectionCard(
          children: <Widget>[
            Text(
              report.resolutionNote.isEmpty ? t('maintenance.breakdownDetail.noNote') : report.resolutionNote,
              style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.text),
            ),
          ],
        ),
      );
    } else if (canManage) {
      children.add(SectionHeading(t('maintenance.breakdownDetail.closeHeading')));
      children.add(SizedBox(height: 10));
      children.add(
        SectionCard(
          children: <Widget>[
            FieldLabel(t('maintenance.breakdownDetail.howHandled')),
            TextField(
              controller: noteController,
              enabled: !isSaving,
              maxLines: 4,
              maxLength: maxNoteLength,
              decoration: InputDecoration(hintText: t('maintenance.breakdownDetail.notePlaceholder')),
            ),
            SizedBox(height: 6),
            Text(
              t('maintenance.breakdownDetail.noteCount', <String, Object?>{'count': noteController.text.length, 'max': maxNoteLength, 'min': minNoteLength}),
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            SizedBox(height: 14),
            FieldLabel(t('maintenance.breakdownDetail.linkedRecord'), hint: t('maintenance.breakdownDetail.optionalHint')),
            AsyncView<List<MaintenanceRecord>>(
              value: ref.watch(vehicleMaintenanceProvider(report.vehiclePublicId)),
              onRetry: () {
                ref.invalidate(vehicleMaintenanceProvider(report.vehiclePublicId));
              },
              builder: (List<MaintenanceRecord> records) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.inputBorder),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: linkedRecordId,
                      isExpanded: true,
                      isDense: true,
                      hint: Text(t('maintenance.breakdownDetail.chooseRecord'), style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
                      style: TextStyle(fontSize: 14, color: AppColors.text),
                      items: <DropdownMenuItem<String?>>[
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(t('maintenance.breakdownDetail.noLink')),
                        ),
                        for (final MaintenanceRecord record in records)
                          DropdownMenuItem<String?>(
                            value: record.publicId,
                            child: Text(
                              '${record.title} · ${formatDate(record.completedOn.isEmpty ? record.startDate : record.completedOn)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: isSaving
                          ? null
                          : (String? value) {
                              setState(() {
                                linkedRecordId = value;
                              });
                            },
                    ),
                  ),
                );
              },
            ),
            if (errorText != null) ...[
              const SizedBox(height: 14),
              ErrorBox(errorText!),
            ],
            SizedBox(height: 16),
            FilledButton(
              onPressed: isSaving ? null : () => resolve(report),
              child: Text(isSaving ? t('maintenance.breakdownDetail.saving') : t('maintenance.breakdownDetail.closeAction')),
            ),
            SizedBox(height: 8),
            NoteText(t('maintenance.breakdownDetail.closeNote')),
          ],
        ),
      );
    }

    return ListView(
      padding: withTabBarInset(context, const EdgeInsets.fromLTRB(16, 16, 16, 32)),
      children: children,
    );
  }
}

String _timeOf(String isoText) {
  if (isoText.isEmpty) {
    return '';
  }
  final DateTime moment = DateTime.parse(isoText).toLocal();
  return '${moment.hour.toString().padLeft(2, '0')}:${moment.minute.toString().padLeft(2, '0')}';
}