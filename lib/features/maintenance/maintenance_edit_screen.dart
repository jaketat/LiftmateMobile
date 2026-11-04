// M2: lập lịch bảo trì và sửa lịch.
// Lưu xong nếu có chuyến đã gán xe trong những ngày đó thì hiện khung cảnh báo vàng
// (server chỉ cảnh báo, không chặn - lấy từ conflictingTrips trong câu trả lời).
import 'package:flutter/cupertino.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.pop
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/i18n.dart';
import '../../core/labels.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import 'maintenance_api.dart';
import 'maintenance_providers.dart';
import '../orders/order_new_sheets.dart' show pickDateTime;
import '../../core/widgets/ios.dart';

/// Ngày server nhận đúng định dạng này, khác với ngày hiện cho người dùng
final DateFormat _serverDateFormat = DateFormat('yyyy-MM-dd');

// Số tiền người dùng gõ có thể có dấu chấm phân tách nghìn ("8.200.000"), bỏ hết rồi mới đổi
double? _parseTien(String raw) {
  String cleaned = raw.trim().replaceAll('.', '').replaceAll(' ', '');
  if (cleaned.isEmpty) {
    return null;
  }
  return double.tryParse(cleaned);
}

class MaintenanceEditScreen extends ConsumerStatefulWidget {
  // null: lập lịch mới. Có id: sửa lịch đang "Đã lên lịch".
  final String? recordId;
  // Xe chọn sẵn khi mở từ màn đền hạn (M4). Chỉ có tác dụng khi lập lịch mới.
  final String? initialVehicleId;

  MaintenanceEditScreen({super.key, this.recordId, this.initialVehicleId});

  @override
  ConsumerState<MaintenanceEditScreen> createState() => _MaintenanceEditScreenState();
}

class _MaintenanceEditScreenState extends ConsumerState<MaintenanceEditScreen> {
  final TextEditingController titleController = TextEditingController();
  final TextEditingController costController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();

  String? vehicleId;
  String kind = 'Periodic';
  DateTime? startDate;
  DateTime? endDate;
  MaintenanceRecord? editingRecord;
  List<MaintenanceTripConflict> conflicts = <MaintenanceTripConflict>[];

  // Đã đổ dữ liệu cũ vào ô một lần, không đè lên chữ người dùng đang sửa
  bool isFilled = false;
  bool isSaving = false;
  String? errorText;

  @override
  void initState() {
    super.initState();
    // Mở từ màn đền hạn thì xe đã biết trước, không bắt chọn lại
    vehicleId = widget.initialVehicleId;
  }

  @override
  void dispose() {
    titleController.dispose();
    costController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  void fillFrom(MaintenanceRecord record) {
    if (isFilled) {
      return;
    }
    isFilled = true;
    editingRecord = record;
    vehicleId = record.vehiclePublicId;
    kind = record.kind;
    titleController.text = record.title;
    descriptionController.text = record.description;
    costController.text = record.estimatedCost == null ? '' : record.estimatedCost!.toStringAsFixed(0);
    startDate = DateTime.parse(record.startDate);
    endDate = DateTime.parse(record.endDate);
  }

  Future<void> pickDate({required bool isStart}) async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await pickDateTime(
      context,
      mode: CupertinoDatePickerMode.date,
      initial: isStart ? (startDate ?? now) : (endDate ?? startDate ?? now),
      minimumDate: DateTime(now.year - 2),
      maximumDate: DateTime(now.year + 2, 12, 31),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      final DateTime day = DateTime(picked.year, picked.month, picked.day);
      if (isStart) {
        startDate = day;
      } else {
        endDate = day;
      }
    });
  }

  Future<void> save() async {
    final String title = titleController.text.trim();
    if (vehicleId == null) {
      setState(() {
        errorText = t('maintenance.edit.chooseVehicle');
      });
      return;
    }
    if (title.isEmpty) {
      setState(() {
        errorText = t('maintenance.edit.enterTitle');
      });
      return;
    }
    if (startDate == null || endDate == null) {
      setState(() {
        errorText = t('maintenance.edit.chooseBothDates');
      });
      return;
    }
    // Tự chặn trước cho khỏi gọi API: server cũng có chặn (INVALID_MAINTENANCE_DATES)
    final int days = endDate!.difference(startDate!).inDays;
    if (endDate!.isBefore(startDate!)) {
      setState(() {
        errorText = t('maintenance.edit.endBeforeStart');
      });
      return;
    }
    if (days > 90) {
      setState(() {
        errorText = t('maintenance.edit.tooLong');
      });
      return;
    }

    setState(() {
      isSaving = true;
      errorText = null;
    });
    try {
      final double? estimatedCost = _parseTien(costController.text);
      final String start = _serverDateFormat.format(startDate!);
      final String end = _serverDateFormat.format(endDate!);
      final String? recordId = editingRecord?.publicId;

      final MaintenanceWriteResult result = recordId == null
          ? await createMaintenance(
              vehiclePublicId: vehicleId!,
              kind: kind,
              title: title,
              startDate: start,
              endDate: end,
              estimatedCost: estimatedCost,
              description: descriptionController.text.trim(),
            )
          : await updateMaintenance(
              id: recordId,
              kind: kind,
              title: title,
              startDate: start,
              endDate: end,
              estimatedCost: estimatedCost,
              description: descriptionController.text.trim(),
            );

      ref.invalidate(maintenancePageProvider);
      ref.invalidate(dueAlertsProvider);
      if (!mounted) {
        return;
      }

      if (result.conflictingTrips.isEmpty) {
        // Không có gì để cảnh báo thì về thẳng danh sách
        showIosToast(context, t('maintenance.edit.saved'));
        context.pop();
        return;
      }

      // Có chuyến bị ảnh hưởng: để người dùng đọc trước khi đóng màn
      setState(() {
        conflicts = result.conflictingTrips;
        isSaving = false;
        editingRecord = result.record;
      });
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

  // Chọn xe từ bảng chọn iOS: biển số · loại xe
  Future<void> pickVehicle(List<VehicleOption> vehicles) async {
    final String? picked = await showIosActionSheet<String>(
      context,
      title: t('maintenance.edit.pickVehicle'),
      options: <IosSheetOption<String>>[
        // Xe nâng không có biển số: chỉ ghi loại xe
        for (final VehicleOption vehicle in vehicles)
          IosSheetOption<String>(
            vehicle.publicId,
            <String>[vehicle.plateNumber, vehicle.vehicleType].where((String part) => part.isNotEmpty).join(' · '),
          ),
      ],
    );
    if (picked != null && mounted) setState(() => vehicleId = picked);
  }

  @override
  Widget build(BuildContext context) {
    final String? recordId = widget.recordId;
    final String title = recordId == null ? t('maintenance.edit.titleNew') : t('maintenance.edit.titleEdit');
    final AsyncValue<List<VehicleOption>> vehiclesValue = ref.watch(vehiclesProvider);
    // Sửa: chờ tải lịch xong mới vẽ form
    final AsyncValue<MaintenanceRecord>? recordValue = recordId == null ? null : ref.watch(maintenanceProvider(recordId));
    final MaintenanceRecord? record = recordValue?.value;
    if (record != null) fillFrom(record);
    final List<VehicleOption>? vehicles = vehiclesValue.value;

    Widget? waiting;
    if (recordValue != null && record == null) {
      waiting = AsyncView<MaintenanceRecord>(
        value: recordValue,
        onRetry: () => ref.invalidate(maintenanceProvider(recordId!)),
        builder: (MaintenanceRecord _) => const SizedBox.shrink(),
      );
    } else if (vehicles == null) {
      waiting = AsyncView<List<VehicleOption>>(
        value: vehiclesValue,
        onRetry: () => ref.invalidate(vehiclesProvider),
        builder: (List<VehicleOption> _) => const SizedBox.shrink(),
      );
    }

    return IosPage(
      title: title,
      slivers: <Widget>[
        if (waiting != null)
          SliverFillRemaining(hasScrollBody: false, child: waiting)
        else
          SliverToBoxAdapter(child: buildForm(vehicles!)),
      ],
    );
  }

  Widget buildForm(List<VehicleOption> vehicles) {
    final bool isEditing = editingRecord != null;
    VehicleOption? vehicle;
    for (final VehicleOption option in vehicles) {
      if (option.publicId == vehicleId) vehicle = option;
    }

    return Column(
      children: <Widget>[
        IosGroup(
          dividerIndent: 62,
          children: <Widget>[
            // Sửa lịch thì không đổi được xe: server không nhận vehiclePublicId khi sửa
            IosRow(
              icon: CupertinoIcons.car_detailed,
              iconColor: vehicle == null ? IosColors.secondaryLabel : AppColors.navy,
              title: vehicle == null
                  ? (editingRecord?.vehicleLabel ?? t('maintenance.edit.pickVehicle'))
                  : (vehicle.plateNumber.isEmpty ? vehicle.vehicleType : vehicle.plateNumber),
              titleWidget: vehicle == null && !isEditing
                  ? Text(t('maintenance.edit.pickVehicle'), style: TextStyle(fontSize: 17, color: IosColors.tertiaryLabel))
                  : null,
              subtitle: vehicle?.vehicleType ?? t('maintenance.edit.vehicle'),
              onTap: isEditing || isSaving ? null : () => pickVehicle(vehicles),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoSlidingSegmentedControl<String>(
                  groupValue: kind,
                  children: <String, Widget>{
                    'Periodic': Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(label(maintenanceKindLabels, 'Periodic'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                    'Repair': Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(label(maintenanceKindLabels, 'Repair'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  },
                  onValueChanged: (String? value) {
                    if (value != null && !isSaving) setState(() => kind = value);
                  },
                ),
              ),
            ),
          ],
        ),
        IosGroup(
          children: <Widget>[
            IosFieldRow(
              label: t('maintenance.edit.jobTitle'),
              controller: titleController,
              placeholder: t('maintenance.edit.titleExample'),
              enabled: !isSaving,
            ),
            IosFieldRow(
              label: t('maintenance.edit.estimatedCost'),
              hint: t('maintenance.edit.optional'),
              controller: costController,
              placeholder: t('maintenance.edit.costExample'),
              enabled: !isSaving,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        IosGroup(
          footer: t('maintenance.edit.daysNote'),
          children: <Widget>[
            IosValueRow(
              label: t('maintenance.edit.from'),
              value: startDate == null ? '—' : formatDateOnly(startDate!),
              valueColor: startDate == null ? null : AppColors.text,
              onTap: isSaving ? null : () => pickDate(isStart: true),
            ),
            IosValueRow(
              label: t('maintenance.edit.to'),
              value: endDate == null ? '—' : formatDateOnly(endDate!),
              valueColor: endDate == null ? null : AppColors.text,
              onTap: isSaving ? null : () => pickDate(isStart: false),
            ),
          ],
        ),
        IosGroup(
          header: t('maintenance.edit.description'),
          headerIcon: CupertinoIcons.text_alignleft,
          children: <Widget>[
            IosTextArea(
              controller: descriptionController,
              placeholder: t('maintenance.edit.descriptionExample'),
              enabled: !isSaving,
              minLines: 3,
            ),
          ],
        ),
        // Khung vàng chỉ hiện sau khi lưu, lấy từ conflictingTrips
        if (conflicts.isNotEmpty)
          IosGroup(
            header: t('maintenance.edit.conflictTitle', <String, Object?>{'count': conflicts.length}),
            headerIcon: CupertinoIcons.exclamationmark_triangle_fill,
            footer: t('maintenance.edit.conflictMessage'),
            dividerIndent: 62,
            children: <Widget>[
              for (final MaintenanceTripConflict conflict in conflicts)
                IosRow(
                  icon: CupertinoIcons.exclamationmark_triangle_fill,
                  iconColor: IosColors.orange,
                  title: conflict.orderCode,
                  subtitle: '${formatDateOnly(DateTime.parse(conflict.startAt))} · ${formatTimeRange(conflict.startAt, conflict.endAt)}',
                  chevron: false,
                ),
            ],
          ),
        if (errorText != null) IosErrorText(errorText!),
        IosFormButton(
          label: isSaving ? t('maintenance.edit.saving') : t('maintenance.edit.save'),
          busy: isSaving,
          onPressed: save,
        ),
      ],
    );
  }
}

// Ngày đã chọn trong bộ chọn: hiện dd/MM/yyyy (không dùng formatDate vì đó nhận chuỗi ISO)
String formatDateOnly(DateTime day) {
  return '${day.day.toString().padLeft(2, '0')}/'
      '${day.month.toString().padLeft(2, '0')}/'
      '${day.year}';
}

// Giờ chạy của chuyến: "08:00 – 12:00"
String formatTimeRange(String startAt, String endAt) {
  String timeOf(String iso) {
    final DateTime moment = DateTime.parse(iso).toLocal();
    return '${moment.hour.toString().padLeft(2, '0')}:${moment.minute.toString().padLeft(2, '0')}';
  }

  return '${timeOf(startAt)} – ${timeOf(endAt)}';
}
