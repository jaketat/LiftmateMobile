// M2: lập lịch bảo trì và sửa lịch.
// Lưu xong nếu có chuyến đã gán xe trong những ngày đó thì hiện khung cảnh báo vàng
// (server chỉ cảnh báo, không chặn - lấy từ conflictingTrips trong câu trả lời).
import 'package:flutter/material.dart';
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
import 'widgets.dart';
import '../../core/widgets/ios.dart';
import '../../core/widgets/page_transition.dart';

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
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart ? (startDate ?? now) : (endDate ?? startDate ?? now),
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
      locale: I18n.locale,
      helpText: isStart ? t('maintenance.edit.from') : t('maintenance.edit.to'),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      if (isStart) {
        startDate = picked;
      } else {
        endDate = picked;
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

  @override
  Widget build(BuildContext context) {
    final String? recordId = widget.recordId;

    Widget body;
    if (recordId == null) {
      body = buildForm();
    } else {
      // Sửa: chờ tải lịch xong mới vẽ form
      final AsyncValue<MaintenanceRecord> recordValue = ref.watch(maintenanceProvider(recordId));
      body = AsyncView<MaintenanceRecord>(
        value: recordValue,
        onRetry: () {
          ref.invalidate(maintenanceProvider(recordId));
        },
        builder: (MaintenanceRecord record) {
          fillFrom(record);
          return buildForm();
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(recordId == null ? t('maintenance.edit.titleNew') : t('maintenance.edit.titleEdit')),
        leading: IconButton(
          icon: Icon(Icons.close),
          onPressed: () {
            context.pop();
          },
        ),
      ),
      body: body,
    );
  }

  Widget buildForm() {
    final bool isEditing = editingRecord != null;

    return AsyncView<List<VehicleOption>>(
      value: ref.watch(vehiclesProvider),
      onRetry: () {
        ref.invalidate(vehiclesProvider);
      },
      builder: (List<VehicleOption> vehicles) {
        final List<Widget> children = <Widget>[
          // Sửa lịch thì không đổi được xe: server không nhận vehiclePublicId khi sửa
          if (!isEditing) ...[
            FieldLabel(t('maintenance.edit.vehicle')),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.inputBorder),
                borderRadius: BorderRadius.circular(10),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: vehicleId,
                  isExpanded: true,
                  hint: Text(t('maintenance.edit.pickVehicle'), style: TextStyle(fontSize: 15, color: AppColors.textMuted)),
                  style: TextStyle(fontSize: 15, color: AppColors.text),
                  items: <DropdownMenuItem<String>>[
                    for (final VehicleOption vehicle in vehicles)
                      DropdownMenuItem<String>(
                        value: vehicle.publicId,
                        child: Text(
                          '${vehicle.plateNumber} · ${vehicle.vehicleType}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: isSaving
                      ? null
                      : (String? value) {
                          setState(() {
                            vehicleId = value;
                          });
                        },
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],
          FieldLabel(t('maintenance.edit.kind')),
          Row(
            children: <Widget>[
              Expanded(
                child: _KindButton(
                  text: label(maintenanceKindLabels, 'Periodic'),
                  isSelected: kind == 'Periodic',
                  onTap: isSaving
                      ? null
                      : () {
                          setState(() {
                            kind = 'Periodic';
                          });
                        },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _KindButton(
                  text: label(maintenanceKindLabels, 'Repair'),
                  isSelected: kind == 'Repair',
                  onTap: isSaving
                      ? null
                      : () {
                          setState(() {
                            kind = 'Repair';
                          });
                        },
                ),
              ),
            ],
          ),
          SizedBox(height: 18),
          FieldLabel(t('maintenance.edit.jobTitle')),
          TextField(
            controller: titleController,
            enabled: !isSaving,
            decoration: InputDecoration(hintText: t('maintenance.edit.titleExample')),
          ),
          SizedBox(height: 18),
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    FieldLabel(t('maintenance.edit.from')),
                    DateField(
                      value: startDate == null ? '' : formatDateOnly(startDate!),
                      onTap: () {
                        pickDate(isStart: true);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    FieldLabel(t('maintenance.edit.to')),
                    DateField(
                      value: endDate == null ? '' : formatDateOnly(endDate!),
                      onTap: () {
                        pickDate(isStart: false);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          NoteText(t('maintenance.edit.daysNote')),
          const SizedBox(height: 18),
          FieldLabel(t('maintenance.edit.estimatedCost'), hint: t('maintenance.edit.optional')),
          TextField(
            controller: costController,
            enabled: !isSaving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(hintText: t('maintenance.edit.costExample')),
          ),
          const SizedBox(height: 18),
          FieldLabel(t('maintenance.edit.description')),
          TextField(
            controller: descriptionController,
            enabled: !isSaving,
            maxLines: 3,
            decoration: InputDecoration(hintText: t('maintenance.edit.descriptionExample')),
          ),
        ];

        // Khung vàng chỉ hiện sau khi lưu, lấy từ conflictingTrips
        if (conflicts.isNotEmpty) {
          children.add(const SizedBox(height: 18));
          children.add(
            WarnBox(
              title: t('maintenance.edit.conflictTitle', <String, Object?>{'count': conflicts.length}),
              message: t('maintenance.edit.conflictMessage'),
              children: <Widget>[
                for (final MaintenanceTripConflict conflict in conflicts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${conflict.orderCode} · ${formatDateOnly(DateTime.parse(conflict.startAt))} · '
                      '${formatTimeRange(conflict.startAt, conflict.endAt)}',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.warnText),
                    ),
                  ),
              ],
            ),
          );
        }

        if (errorText != null) {
          children.add(const SizedBox(height: 18));
          children.add(ErrorBox(errorText!));
        }

        children.add(const SizedBox(height: 24));
        children.add(
          FilledButton(
            onPressed: isSaving ? null : save,
            child: Text(isSaving ? t('maintenance.edit.saving') : t('maintenance.edit.save')),
          ),
        );

        return ListView(
          padding: withTabBarInset(context, const EdgeInsets.fromLTRB(16, 16, 16, 32)),
          children: children,
        );
      },
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

/// Nút chọn loại lịch, nửa nền ứng với ảnh màn hình.
class _KindButton extends StatelessWidget {
  final String text;
  final bool isSelected;
  final VoidCallback? onTap;

  const _KindButton({required this.text, required this.isSelected, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.navy : AppColors.surface,
          border: Border.all(color: isSelected ? AppColors.navy : AppColors.inputBorder),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AppColors.label,
          ),
        ),
      ),
    );
  }
}