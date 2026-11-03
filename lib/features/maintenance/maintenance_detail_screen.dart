// M3: chi tiết một lịch bảo trì - hoàn thành, hủy, sửa chi phí.
// Lịch đã hoàn thành thì ẩn form hoàn thành, đổi thành nút sửa chi phí; không hủy được nữa.
import 'package:flutter/material.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push, context.pop
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/labels.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import 'maintenance_api.dart';
import 'maintenance_edit_screen.dart' show formatDateOnly;
import 'maintenance_providers.dart';
import 'widgets.dart';
import '../../core/widgets/ios.dart';
import '../../core/widgets/page_transition.dart';

// Độ dài lý do server bắt buộc (10-500 ký tự) cho cả hủy lịch lẫn sửa chi phí
const int minReasonLength = 10;
const int maxReasonLength = 500;

class MaintenanceDetailScreen extends ConsumerStatefulWidget {
  final String recordId;

  MaintenanceDetailScreen({super.key, required this.recordId});

  @override
  ConsumerState<MaintenanceDetailScreen> createState() => _MaintenanceDetailScreenState();
}

class _MaintenanceDetailScreenState extends ConsumerState<MaintenanceDetailScreen> {
  final TextEditingController completedOnController = TextEditingController();
  final TextEditingController actualCostController = TextEditingController();
  final TextEditingController engineHoursController = TextEditingController();
  final TextEditingController odometerController = TextEditingController();

  bool isSaving = false;
  String? errorText;
  // Lỗi riêng của ô giờ máy, để khoanh đúng ô cần sửa
  String? engineHoursError;

  @override
  void initState() {
    super.initState();
    // Hoàn thành bằng tay: mặc định là hôm nay
    completedOnController.text = formatDateOnly(DateTime.now());
  }

  @override
  void dispose() {
    completedOnController.dispose();
    actualCostController.dispose();
    engineHoursController.dispose();
    odometerController.dispose();
    super.dispose();
  }

  Future<void> pickCompletedOn() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      locale: I18n.locale,
      helpText: t('maintenance.detail.completedOnHelp'),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      completedOnController.text = formatDateOnly(picked);
    });
  }

  Future<void> complete(MaintenanceRecord record, bool engineHoursRequired) async {
    final double? actualCost = double.tryParse(actualCostController.text.trim());
    if (actualCostController.text.trim().isEmpty || actualCost == null) {
      setState(() {
        errorText = t('maintenance.detail.enterActualCost');
      });
      return;
    }
    if (completedOnController.text.trim().isEmpty) {
      setState(() {
        errorText = t('maintenance.detail.chooseCompletedOn');
      });
      return;
    }

    // Lịch định kỳ của xe có theo dõi giờ máy thì ô này bắt buộc, thiếu là báo đúng ô
    double? engineHours;
    String? missingEngineHours;
    if (engineHoursRequired) {
      engineHours = double.tryParse(engineHoursController.text.trim());
      if (engineHours == null) {
        missingEngineHours = t('maintenance.detail.engineHoursRequired');
      }
    }

    setState(() {
      isSaving = true;
      errorText = null;
      engineHoursError = missingEngineHours;
    });
    try {
      await completeMaintenance(
        id: record.publicId,
        // Ô này hiện dd/MM/yyyy, server nhận yyyy-MM-dd
        completedOn: _toServerDate(completedOnController.text),
        actualCost: actualCost,
        engineHours: engineHours,
        odometerKm: int.tryParse(odometerController.text.trim()),
      );
      ref.invalidate(maintenancePageProvider);
      ref.invalidate(maintenanceProvider(record.publicId));
      ref.invalidate(dueAlertsProvider);
      if (!mounted) {
        return;
      }
      showIosToast(context, t('maintenance.detail.completedToast'));
      context.pop();
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

  /// Hỏi lý do rồi mới hủy. Server bắt buộc 10-500 ký tự nên kiểm tra ngay ở app.
  Future<void> askCancel(MaintenanceRecord record) async {
    final String? reason = await showReasonDialog(
      context,
      title: t('maintenance.detail.cancelTitle'),
      message: t('maintenance.detail.cancelMessage'),
      confirmText: t('maintenance.detail.cancelConfirm'),
    );
    if (reason == null || !mounted) {
      return;
    }
    setState(() {
      isSaving = true;
      errorText = null;
    });
    try {
      await cancelMaintenance(record.publicId, reason);
      ref.invalidate(maintenancePageProvider);
      ref.invalidate(maintenanceProvider(record.publicId));
      ref.invalidate(dueAlertsProvider);
      if (!mounted) {
        return;
      }
      showIosToast(context, t('maintenance.detail.cancelledToast'));
      context.pop();
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

  /// Sửa chi phí thật sau khi hoàn thành. Bắt buộc có lý do để lưu nhật ký.
  Future<void> askCorrectCost(MaintenanceRecord record) async {
    final ({double cost, String reason})? input = await showCostDialog(
      context,
      currentCost: record.actualCost,
    );
    if (input == null || !mounted) {
      return;
    }
    setState(() {
      isSaving = true;
      errorText = null;
    });
    try {
      await correctActualCost(record.publicId, input.cost, input.reason);
      ref.invalidate(maintenancePageProvider);
      ref.invalidate(maintenanceProvider(record.publicId));
      if (!mounted) {
        return;
      }
      showIosToast(context, t('maintenance.detail.costCorrectedToast'));
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
    final String recordId = widget.recordId;
    final AsyncValue<MaintenanceRecord> recordValue = ref.watch(maintenanceProvider(recordId));

    return Scaffold(
      appBar: AppBar(
        title: Text(recordValue.value?.title ?? t('maintenance.detail.title')),
        // Lịch còn "Đã lên lịch" mới sửa được. Lịch đã xong hoặc đã hủy thì không có nút này.
        actions: <Widget>[
          if (recordValue.value?.status == 'Scheduled')
            TextButton(
              onPressed: () {
                context.push('/maintenance/${widget.recordId}/edit');
              },
              child: Text(t('maintenance.detail.editSchedule')),
            ),
        ],
      ),
      body: AsyncView<MaintenanceRecord>(
        value: recordValue,
        onRetry: () {
          ref.invalidate(maintenanceProvider(recordId));
        },
        builder: (MaintenanceRecord record) {
          return buildBody(record);
        },
      ),
    );
  }

  Widget buildBody(MaintenanceRecord record) {
    // Giờ máy chỉ bắt buộc với lịch định kỳ của xe có đặt chu kỳ theo giờ máy.
    // Hỏi định mức của xe để biết có theo dõi giờ máy không.
    final AsyncValue<VehicleMaintenancePlan> planValue =
        ref.watch(maintenancePlanProvider(record.vehiclePublicId));
    final bool engineHoursRequired = record.kind == 'Periodic' &&
        planValue.value != null &&
        planValue.value!.intervalHours != null;

    final List<Widget> children = <Widget>[
      SectionCard(
        children: <Widget>[
          DetailRow(
            label: t('maintenance.detail.vehicle'),
            value: record.vehicleLabel,
            trailing: record.vehicleDeleted
                ? Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: ToneChip(t('maintenance.detail.vehicleDeleted'), tone: Tone.danger),
                  )
                : null,
          ),
          DetailRow(
            label: t('maintenance.detail.schedule'),
            value: '${formatDate(record.startDate)} – ${formatDate(record.endDate)} · '
                '${label(maintenanceKindLabels, record.kind).toLowerCase()}',
          ),
          Row(
            children: <Widget>[
              SizedBox(width: 92, child: Text(t('maintenance.detail.status'), style: TextStyle(fontSize: 14, color: AppColors.textMuted))),
              ToneChip(label(maintenanceStatusLabels, record.status), tone: _toneFor(record.status)),
            ],
          ),
          if (record.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(record.description, style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.textMuted)),
          ],
          // Xe đã xóa thì không mở được màn của xe nữa
          if (!record.vehicleDeleted)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () {
                  context.push('/maintenance/plan/${record.vehiclePublicId}');
                },
                child: Text(t('maintenance.detail.viewPlan')),
              ),
            ),
        ],
      ),
      SizedBox(height: 16),
    ];

    if (record.status == 'Scheduled') {
      // Lịch quá hạn thì nhắc trên đầu form hoàn thành
      if (record.isOverdue) {
        children.add(
          WarnBox(
            title: t('maintenance.detail.overdueTitle'),
            message: t('maintenance.detail.overdueMessage'),
          ),
        );
        children.add(const SizedBox(height: 16));
      }

      children.add(SectionHeading(t('maintenance.detail.completeHeading')));
      children.add(SizedBox(height: 10));
      children.add(
        SectionCard(
          children: <Widget>[
            FieldLabel(t('maintenance.detail.completedOn')),
            DateField(
              value: completedOnController.text,
              onTap: pickCompletedOn,
            ),
            const SizedBox(height: 14),
            FieldLabel(t('maintenance.detail.actualCostLabel')),
            TextField(
              controller: actualCostController,
              enabled: !isSaving,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(hintText: t('maintenance.detail.costExample')),
            ),
            const SizedBox(height: 14),
            FieldLabel(
              t('maintenance.detail.engineHoursLabel'),
              hint: engineHoursRequired ? t('maintenance.detail.required') : t('maintenance.detail.optional'),
            ),
            TextField(
              controller: engineHoursController,
              enabled: !isSaving,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              // Ô bắt buộc thì viền đỏ ngay từ đầu để thấy rõ phải điền
              style: TextStyle(fontSize: 15, color: engineHoursRequired ? AppColors.errorText : AppColors.text),
              decoration: InputDecoration(
                hintText: t('maintenance.detail.numberExample'),
                hintStyle: TextStyle(fontSize: 15, color: engineHoursRequired ? AppColors.errorText.withValues(alpha: 0.5) : AppColors.textMuted),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: engineHoursRequired ? AppColors.errorText : AppColors.inputBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: engineHoursRequired ? AppColors.errorText : AppColors.navy, width: 1.5),
                ),
              ),
            ),
            if (engineHoursRequired)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  engineHoursError ?? t('maintenance.detail.engineHoursRequired'),
                  style: TextStyle(fontSize: 12, color: engineHoursError != null ? AppColors.errorText : AppColors.warnText),
                ),
              ),
            // Nói rõ điền số gì: bộ đếm giờ máy hiện tại của xe
            if (planValue.value != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  t('maintenance.detail.currentEngineHours', <String, Object?>{'hours': formatNumber(planValue.value!.currentEngineHours)}),
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ),
            const SizedBox(height: 14),
            FieldLabel(t('maintenance.detail.odometerLabel'), hint: t('maintenance.detail.optional')),
            TextField(
              controller: odometerController,
              enabled: !isSaving,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(hintText: t('maintenance.detail.numberExample')),
            ),
            if (planValue.value != null && planValue.value!.currentOdometerKm != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  t('maintenance.detail.currentOdometer', <String, Object?>{'km': formatNumber(planValue.value!.currentOdometerKm)}),
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ),
            if (errorText != null) ...[
              const SizedBox(height: 14),
              ErrorBox(errorText!),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: isSaving ? null : () => complete(record, engineHoursRequired),
              child: Text(isSaving ? t('maintenance.detail.saving') : t('maintenance.detail.completeAction')),
            ),
            const SizedBox(height: 18),
            // Hủy lịch: chữ đỏ, bấm mới mở ô nhập lý do
            Center(
              child: TextButton(
                onPressed: isSaving ? null : () => askCancel(record),
                style: TextButton.styleFrom(foregroundColor: AppColors.errorText),
                child: Text(t('maintenance.detail.cancelAction')),
              ),
            ),
          ],
        ),
      );
    } else if (record.status == 'Completed') {
      // Đã xong: không sửa lịch, không hủy được. Chỉ còn sửa chi phí.
      children.add(
        SectionCard(
          children: <Widget>[
            SectionHeading(t('maintenance.detail.completedHeading')),
            const SizedBox(height: 10),
            DetailRow(label: t('maintenance.detail.completedOn'), value: formatDate(record.completedOn)),
            DetailRow(
              label: t('maintenance.detail.actualCost'),
              value: record.actualCost == null ? '--' : formatMoney(record.actualCost),
            ),
            if (record.engineHoursAtCompletion != null)
              DetailRow(label: t('maintenance.detail.engineHoursLabel'), value: formatNumber(record.engineHoursAtCompletion)),
            if (record.odometerKmAtCompletion != null)
              DetailRow(label: t('maintenance.detail.odometerLabel'), value: formatNumber(record.odometerKmAtCompletion)),
          ],
        ),
      );
      children.add(SizedBox(height: 16));
      children.add(
        NoteText(t('maintenance.detail.completedNote')),
      );
      children.add(const SizedBox(height: 12));
      children.add(
        OutlinedButton(
          onPressed: isSaving ? null : () => askCorrectCost(record),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(t('maintenance.detail.correctCost')),
        ),
      );
      if (errorText != null) {
        children.add(const SizedBox(height: 14));
        children.add(ErrorBox(errorText!));
      }
    } else {
      // Đã hủy: chỉ hiện lý do hủy, không có nút thao tác nào
      children.add(
        SectionCard(
          children: <Widget>[
            SectionHeading(t('maintenance.detail.cancelReasonHeading')),
            const SizedBox(height: 6),
            Text(
              record.cancelReason.isEmpty ? t('maintenance.detail.noReason') : record.cancelReason,
              style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.text),
            ),
            if (record.cancelledAt.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                t('maintenance.detail.cancelledAt', <String, Object?>{'time': formatDateTime(record.cancelledAt)}),
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
            ],
          ],
        ),
      );
    }

    return ListView(
      padding: withTabBarInset(context, const EdgeInsets.all(16)),
      children: children,
    );
  }
}

Tone _toneFor(String status) {
  if (status == 'Completed') {
    return Tone.ok;
  }
  if (status == 'Cancelled') {
    return Tone.danger;
  }
  return Tone.neutral;
}

// "16/10/2026" -> "2026-10-16" đúng thứ server nhận
String _toServerDate(String ngayHienThi) {
  final List<String> parts = ngayHienThi.split('/');
  if (parts.length != 3) {
    return ngayHienThi;
  }
  return '${parts[2]}-${parts[1]}-${parts[0]}';
}

// -------------------------------------------------- Hộp thoại nhập lý do

/// Hộp thoại nhập lý do 10-500 ký tự, dùng chung cho hủy lịch.
Future<String?> showReasonDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmText,
}) {
  final TextEditingController controller = TextEditingController();
  String? error;

  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) {
          void confirm() {
            final String reason = controller.text.trim();
            if (reason.length < minReasonLength) {
              setDialogState(() {
                error = t('maintenance.detail.reasonMin', <String, Object?>{'min': minReasonLength});
              });
              return;
            }
            if (reason.length > maxReasonLength) {
              setDialogState(() {
                error = t('maintenance.detail.reasonMax', <String, Object?>{'max': maxReasonLength});
              });
              return;
            }
            Navigator.of(dialogContext).pop(reason);
          }

          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(message, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  maxLength: maxReasonLength,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: t('maintenance.detail.reasonHint'),
                    errorText: error,
                  ),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: Text(t('common.cancel')),
              ),
              FilledButton(
                onPressed: confirm,
                child: Text(confirmText),
              ),
            ],
          );
        },
      );
    },
  ).whenComplete(controller.dispose);
}

// ------------------------------------------- Hộp thoại sửa chi phí thật

/// Hộp thoại sửa chi phí: bắt buộc có chi phí mới và lý do 10-500 ký tự.
Future<({double cost, String reason})?> showCostDialog(
  BuildContext context, {
  required double? currentCost,
}) {
  final TextEditingController costController =
      TextEditingController(text: currentCost == null ? '' : currentCost.toStringAsFixed(0));
  final TextEditingController reasonController = TextEditingController();
  String? error;

  return showDialog<({double cost, String reason})>(
    context: context,
    builder: (BuildContext dialogContext) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) {
          void confirm() {
            final double? cost = double.tryParse(costController.text.trim());
            if (cost == null) {
              setDialogState(() {
                error = t('maintenance.detail.enterNewCost');
              });
              return;
            }
            final String reason = reasonController.text.trim();
            if (reason.length < minReasonLength) {
              setDialogState(() {
                error = t('maintenance.detail.reasonMin', <String, Object?>{'min': minReasonLength});
              });
              return;
            }
            if (reason.length > maxReasonLength) {
              setDialogState(() {
                error = t('maintenance.detail.reasonMax', <String, Object?>{'max': maxReasonLength});
              });
              return;
            }
            Navigator.of(dialogContext).pop((cost: cost, reason: reason));
          }

          return AlertDialog(
            title: Text(t('maintenance.detail.correctCost')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                FieldLabel(t('maintenance.detail.newCostLabel')),
                TextField(
                  controller: costController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(hintText: t('maintenance.detail.costExample')),
                ),
                const SizedBox(height: 14),
                FieldLabel(t('maintenance.detail.correctReason')),
                TextField(
                  controller: reasonController,
                  maxLines: 2,
                  maxLength: maxReasonLength,
                  decoration: InputDecoration(hintText: t('maintenance.detail.reasonHint')),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: TextStyle(fontSize: 13, color: AppColors.errorText)),
                ],
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: Text(t('common.cancel')),
              ),
              FilledButton(onPressed: confirm, child: Text(t('common.save'))),
            ],
          );
        },
      );
    },
  ).whenComplete(() {
    costController.dispose();
    reasonController.dispose();
  });
}