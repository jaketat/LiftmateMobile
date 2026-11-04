// M3: chi tiết một lịch bảo trì - hoàn thành, hủy, sửa chi phí.
// Lịch đã hoàn thành thì ẩn form hoàn thành, đổi thành nút sửa chi phí; không hủy được nữa.
import 'package:flutter/cupertino.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push, context.pop
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/labels.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../orders/order_new_sheets.dart' show pickDateTime;
import 'maintenance_api.dart';
import 'maintenance_edit_screen.dart' show formatDateOnly;
import 'maintenance_providers.dart';
import '../../core/widgets/ios.dart';

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
    // Không chọn được ngày trong tương lai: chỉ ghi việc đã làm xong
    final DateTime? picked = await pickDateTime(
      context,
      mode: CupertinoDatePickerMode.date,
      initial: now,
      minimumDate: DateTime(now.year - 2),
      maximumDate: now,
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
    final MaintenanceRecord? record = recordValue.value;
    if (record == null) {
      return IosPage(
        title: t('maintenance.detail.title'),
        slivers: <Widget>[
          SliverFillRemaining(
            hasScrollBody: false,
            child: AsyncView<MaintenanceRecord>(
              value: recordValue,
              onRetry: () => ref.invalidate(maintenanceProvider(recordId)),
              builder: (MaintenanceRecord _) => const SizedBox.shrink(),
            ),
          ),
        ],
      );
    }
    return IosPage(
      title: record.title,
      onRefresh: () => ref.refresh(maintenanceProvider(recordId).future),
      // Lịch còn "Đã lên lịch" mới sửa được. Lịch đã xong hoặc đã hủy thì không có nút này.
      trailing: record.status == 'Scheduled'
          ? IosGlassIconButton(
              icon: CupertinoIcons.pencil,
              nativeSymbol: 'pencil',
              tooltip: t('maintenance.detail.editSchedule'),
              onPressed: () => context.push('/maintenance/${widget.recordId}/edit'),
            )
          : null,
      slivers: <Widget>[SliverToBoxAdapter(child: buildBody(record))],
    );
  }

  Widget buildBody(MaintenanceRecord record) {
    // Giờ máy chỉ bắt buộc với lịch định kỳ của xe có đặt chu kỳ theo giờ máy.
    // Hỏi định mức của xe để biết có theo dõi giờ máy không.
    final AsyncValue<VehicleMaintenancePlan> planValue = ref.watch(maintenancePlanProvider(record.vehiclePublicId));
    final VehicleMaintenancePlan? plan = planValue.value;
    final bool engineHoursRequired = record.kind == 'Periodic' && plan != null && plan.intervalHours != null;
    final bool isRepair = record.kind == 'Repair';

    final List<Widget> children = <Widget>[
      IosGroup(
        dividerIndent: 62,
        footer: record.description.isEmpty ? null : record.description,
        children: <Widget>[
          IosRow(
            icon: CupertinoIcons.car_detailed,
            iconColor: record.vehicleDeleted ? IosColors.secondaryLabel : AppColors.navy,
            title: record.vehicleLabel,
            subtitle: t('maintenance.detail.vehicle'),
            trailing: record.vehicleDeleted ? IosPill(t('maintenance.detail.vehicleDeleted'), color: IosColors.red) : null,
            chevron: false,
          ),
          IosRow(
            icon: isRepair ? CupertinoIcons.hammer_fill : CupertinoIcons.wrench_fill,
            iconColor: isRepair ? IosColors.orange : AppColors.navy,
            title: '${formatDate(record.startDate)} – ${formatDate(record.endDate)}',
            subtitle: label(maintenanceKindLabels, record.kind),
            trailing: IosPill(label(maintenanceStatusLabels, record.status), color: _statusColor(record.status)),
            chevron: false,
          ),
          // Xe đã xóa thì không mở được màn của xe nữa
          if (!record.vehicleDeleted)
            IosRow(
              icon: CupertinoIcons.chart_bar_square_fill,
              iconColor: IosColors.blue,
              title: t('maintenance.detail.viewPlan'),
              onTap: () => context.push('/maintenance/plan/${record.vehiclePublicId}'),
            ),
        ],
      ),
    ];

    if (record.status == 'Scheduled') {
      // Lịch quá hạn thì nhắc trên đầu form hoàn thành
      if (record.isOverdue) {
        children.add(IosGroup(
          dividerIndent: 62,
          children: <Widget>[
            IosRow(
              icon: CupertinoIcons.exclamationmark_triangle_fill,
              iconColor: IosColors.red,
              titleWidget: Text(
                t('maintenance.detail.overdueTitle'),
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.errorText),
              ),
              title: t('maintenance.detail.overdueTitle'),
              subtitle: t('maintenance.detail.overdueMessage'),
              chevron: false,
            ),
          ],
        ));
      }

      final List<String> engineNotes = <String>[
        if (engineHoursRequired) engineHoursError ?? t('maintenance.detail.engineHoursRequired'),
        // Nói rõ điền số gì: bộ đếm giờ máy hiện tại của xe
        if (plan != null) t('maintenance.detail.currentEngineHours', <String, Object?>{'hours': formatNumber(plan.currentEngineHours)}),
        if (plan != null && plan.currentOdometerKm != null)
          t('maintenance.detail.currentOdometer', <String, Object?>{'km': formatNumber(plan.currentOdometerKm)}),
      ];
      children.add(IosGroup(
        header: t('maintenance.detail.completeHeading'),
        headerIcon: CupertinoIcons.checkmark_seal_fill,
        footerWidget: engineNotes.isEmpty
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: <Widget>[
                  for (final String note in engineNotes)
                    Text(
                      note,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: note == engineHoursError ? AppColors.errorText : IosColors.secondaryLabel,
                      ),
                    ),
                ],
              ),
        children: <Widget>[
          IosValueRow(
            label: t('maintenance.detail.completedOn'),
            value: completedOnController.text,
            valueColor: AppColors.text,
            onTap: isSaving ? null : pickCompletedOn,
          ),
          IosFieldRow(
            label: t('maintenance.detail.actualCostLabel'),
            controller: actualCostController,
            placeholder: t('maintenance.detail.costExample'),
            enabled: !isSaving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          IosFieldRow(
            label: t('maintenance.detail.engineHoursLabel'),
            hint: engineHoursRequired ? t('maintenance.detail.required') : t('maintenance.detail.optional'),
            controller: engineHoursController,
            placeholder: t('maintenance.detail.numberExample'),
            enabled: !isSaving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            // Ô bắt buộc thì chữ đỏ ngay từ đầu để thấy rõ phải điền
            highlight: engineHoursRequired,
          ),
          IosFieldRow(
            label: t('maintenance.detail.odometerLabel'),
            hint: t('maintenance.detail.optional'),
            controller: odometerController,
            placeholder: t('maintenance.detail.numberExample'),
            enabled: !isSaving,
            keyboardType: TextInputType.number,
          ),
        ],
      ));
      if (errorText != null) children.add(IosErrorText(errorText!));
      children.add(IosFormButton(
        label: isSaving ? t('maintenance.detail.saving') : t('maintenance.detail.completeAction'),
        icon: CupertinoIcons.checkmark_alt,
        busy: isSaving,
        onPressed: () => complete(record, engineHoursRequired),
      ));
      // Hủy lịch: chữ đỏ, bấm mới mở ô nhập lý do
      children.add(IosGroup(
        children: <Widget>[
          IosRow(
            title: t('maintenance.detail.cancelAction'),
            destructive: true,
            centered: true,
            onTap: isSaving ? null : () => askCancel(record),
          ),
        ],
      ));
    } else if (record.status == 'Completed') {
      // Đã xong: không sửa lịch, không hủy được. Chỉ còn sửa chi phí.
      children.add(IosGroup(
        header: t('maintenance.detail.completedHeading'),
        headerIcon: CupertinoIcons.checkmark_seal_fill,
        footer: t('maintenance.detail.completedNote'),
        children: <Widget>[
          IosValueRow(label: t('maintenance.detail.completedOn'), value: formatDate(record.completedOn)),
          IosValueRow(
            label: t('maintenance.detail.actualCost'),
            value: record.actualCost == null ? '--' : formatMoney(record.actualCost),
            valueColor: AppColors.text,
          ),
          if (record.engineHoursAtCompletion != null)
            IosValueRow(label: t('maintenance.detail.engineHoursLabel'), value: formatNumber(record.engineHoursAtCompletion)),
          if (record.odometerKmAtCompletion != null)
            IosValueRow(label: t('maintenance.detail.odometerLabel'), value: formatNumber(record.odometerKmAtCompletion)),
        ],
      ));
      children.add(IosGroup(
        children: <Widget>[
          IosRow(
            title: t('maintenance.detail.correctCost'),
            centered: true,
            titleWidget: Text(
              t('maintenance.detail.correctCost'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: IosColors.blue),
            ),
            onTap: isSaving ? null : () => askCorrectCost(record),
          ),
        ],
      ));
      if (errorText != null) children.add(IosErrorText(errorText!));
    } else {
      // Đã hủy: chỉ hiện lý do hủy, không có nút thao tác nào
      children.add(IosGroup(
        header: t('maintenance.detail.cancelReasonHeading'),
        headerIcon: CupertinoIcons.xmark_circle_fill,
        footer: record.cancelledAt.isEmpty ? null : t('maintenance.detail.cancelledAt', <String, Object?>{'time': formatDateTime(record.cancelledAt)}),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              record.cancelReason.isEmpty ? t('maintenance.detail.noReason') : record.cancelReason,
              style: TextStyle(fontSize: 16, height: 1.4, color: AppColors.text),
            ),
          ),
        ],
      ));
    }

    return Column(children: children);
  }
}

Color _statusColor(String status) {
  if (status == 'Completed') return IosColors.green;
  if (status == 'Cancelled') return IosColors.red;
  return AppColors.navy;
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
}) async {
  final TextEditingController controller = TextEditingController();
  final bool? ok = await showIosDialog<bool>(
    context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) => StatefulBuilder(
      builder: (BuildContext context, StateSetter setDialogState) {
        final int length = controller.text.trim().length;
        return IosDialog(
          title: title,
          message: message,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: <Widget>[
              IosDialogField(
                controller: controller,
                autofocus: true,
                placeholder: t('maintenance.detail.reasonHint'),
                maxLines: 4,
                maxLength: maxReasonLength,
                onChanged: (String _) => setDialogState(() {}),
              ),
              // Chưa đủ 10 ký tự thì nhắc ngay, nút xác nhận còn khóa
              if (length > 0 && length < minReasonLength)
                Text(
                  t('maintenance.detail.reasonMin', <String, Object?>{'min': minReasonLength}),
                  style: TextStyle(fontSize: 13, color: AppColors.errorText),
                ),
            ],
          ),
          actions: <IosDialogAction>[
            IosDialogAction(
              label: t('common.cancel'),
              style: IosDialogActionStyle.primary,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            IosDialogAction(
              label: confirmText,
              style: IosDialogActionStyle.destructive,
              onPressed: length < minReasonLength ? null : () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    ),
  );
  final String reason = controller.text.trim();
  controller.dispose();
  return ok == true ? reason : null;
}

// ------------------------------------------- Hộp thoại sửa chi phí thật

/// Hộp thoại sửa chi phí: bắt buộc có chi phí mới và lý do 10-500 ký tự.
Future<({double cost, String reason})?> showCostDialog(
  BuildContext context, {
  required double? currentCost,
}) async {
  final TextEditingController costController =
      TextEditingController(text: currentCost == null ? '' : currentCost.toStringAsFixed(0));
  final TextEditingController reasonController = TextEditingController();
  final bool? ok = await showIosDialog<bool>(
    context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) => StatefulBuilder(
      builder: (BuildContext context, StateSetter setDialogState) {
        final bool costValid = double.tryParse(costController.text.trim()) != null;
        final int length = reasonController.text.trim().length;
        return IosDialog(
          title: t('maintenance.detail.correctCost'),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: 10,
            children: <Widget>[
              IosDialogField(
                controller: costController,
                autofocus: true,
                placeholder: t('maintenance.detail.newCostLabel'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (String _) => setDialogState(() {}),
              ),
              IosDialogField(
                controller: reasonController,
                placeholder: t('maintenance.detail.correctReason'),
                maxLines: 3,
                maxLength: maxReasonLength,
                onChanged: (String _) => setDialogState(() {}),
              ),
              if (length > 0 && length < minReasonLength)
                Text(
                  t('maintenance.detail.reasonMin', <String, Object?>{'min': minReasonLength}),
                  style: TextStyle(fontSize: 13, color: AppColors.errorText),
                ),
            ],
          ),
          actions: <IosDialogAction>[
            IosDialogAction(
              label: t('common.cancel'),
              style: IosDialogActionStyle.secondary,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            IosDialogAction(
              label: t('common.save'),
              style: IosDialogActionStyle.primary,
              onPressed: !costValid || length < minReasonLength ? null : () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    ),
  );
  final double? cost = double.tryParse(costController.text.trim());
  final String reason = reasonController.text.trim();
  costController.dispose();
  reasonController.dispose();
  return ok == true && cost != null ? (cost: cost, reason: reason) : null;
}
