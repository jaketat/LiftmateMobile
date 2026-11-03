// M5: định mức bảo trì của một xe - xem và sửa (giờ máy, tháng, km).
// Ô nào để trống thì xe không theo đối tiêu đó. Đến tiêu chí nào trước thì nhắc trước.
//
// Editor tách riêng thành widget vì dùng ở hai chỗ: nằm ngay dưới danh sách đền hạn (M4, đúng như ảnh màn hình)
// và mở riêng thành một màn khi bấm từ chi tiết lịch.
import 'package:flutter/material.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../auth/session_provider.dart';
import 'maintenance_api.dart';
import 'maintenance_providers.dart';
import 'widgets.dart';
import '../../core/widgets/ios.dart';

// Giới hạn server chấp nhận, kiểm tra sẵn ở app cho khỏi gọi API
const int minIntervalHours = 10;
const int maxIntervalHours = 10000;
const int minIntervalMonths = 1;
const int maxIntervalMonths = 60;
const int minIntervalKm = 1000;
const int maxIntervalKm = 100000;

class MaintenancePlanScreen extends ConsumerWidget {
  final String vehicleId;

  const MaintenancePlanScreen({super.key, required this.vehicleId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(t('maintenance.plan.title'))),
      body: MaintenancePlanEditor(vehicleId: vehicleId),
    );
  }
}

class MaintenancePlanEditor extends ConsumerStatefulWidget {
  final String vehicleId;
  // Tên xe hiện sẵn ở tiêu đề. Không có thì tra trong danh sách xe đã tải.
  final String? vehicleLabel;

  const MaintenancePlanEditor({super.key, required this.vehicleId, this.vehicleLabel});

  @override
  ConsumerState<MaintenancePlanEditor> createState() => _MaintenancePlanEditorState();
}

class _MaintenancePlanEditorState extends ConsumerState<MaintenancePlanEditor> {
  final TextEditingController hoursController = TextEditingController();
  final TextEditingController monthsController = TextEditingController();
  final TextEditingController kmController = TextEditingController();

  // Đã đổ định mức cũ vào ô một lần, không đè lên chữ người dùng đang sửa
  bool isFilled = false;
  bool isSaving = false;
  String? errorText;

  @override
  void didUpdateWidget(covariant MaintenancePlanEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Editor nằm ngay dưới danh sách đền hạn: bấm sang xe khác thì Flutter vẫn giữ
    // State cũ, mà định mức đã điền vào ô thuộc về xe trước. Xóa ô rồi điền lại.
    if (oldWidget.vehicleId != widget.vehicleId) {
      hoursController.clear();
      monthsController.clear();
      kmController.clear();
      isFilled = false;
      errorText = null;
    }
  }

  @override
  void dispose() {
    hoursController.dispose();
    monthsController.dispose();
    kmController.dispose();
    super.dispose();
  }

  void fillFrom(VehicleMaintenancePlan plan) {
    if (isFilled) {
      return;
    }
    isFilled = true;
    hoursController.text = plan.intervalHours == null ? '' : _so(plan.intervalHours!);
    monthsController.text = plan.intervalMonths == null ? '' : '${plan.intervalMonths}';
    kmController.text = plan.intervalKm == null ? '' : '${plan.intervalKm}';
  }

  // Số giờ máy có phần thập phân, các ô kia là số nguyên
  String _so(double value) {
    return value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';
  }

  /// Đọc ô: trống là null (không theo đối tiêu đó). Sai giới hạn thì trả lỗi.
  ({int? value, String? error}) readInterval(TextEditingController controller, int min, int max, String ten) {
    final String raw = controller.text.trim();
    if (raw.isEmpty) {
      return (value: null, error: null);
    }
    final int? parsed = int.tryParse(raw);
    if (parsed == null) {
      return (value: null, error: t('maintenance.plan.notInteger', <String, Object?>{'name': ten}));
    }
    if (parsed < min || parsed > max) {
      return (value: null, error: t('maintenance.plan.outOfRange', <String, Object?>{'name': ten, 'min': min, 'max': max}));
    }
    return (value: parsed, error: null);
  }

  Future<void> save() async {
    final ({int? value, String? error}) hours =
        readInterval(hoursController, minIntervalHours, maxIntervalHours, t('maintenance.plan.hoursName'));
    final ({int? value, String? error}) months =
        readInterval(monthsController, minIntervalMonths, maxIntervalMonths, t('maintenance.plan.monthsName'));
    final ({int? value, String? error}) km =
        readInterval(kmController, minIntervalKm, maxIntervalKm, t('maintenance.plan.kmName'));

    final String? firstError = hours.error ?? months.error ?? km.error;
    if (firstError != null) {
      setState(() {
        errorText = firstError;
      });
      return;
    }

    setState(() {
      isSaving = true;
      errorText = null;
    });
    try {
      await setMaintenancePlan(
        vehicleId: widget.vehicleId,
        intervalHours: hours.value?.toDouble(),
        intervalMonths: months.value,
        intervalKm: km.value,
      );
      // Sửa định mức xong thì cảnh báo đền hạn phải tính lại
      ref.invalidate(maintenancePlanProvider(widget.vehicleId));
      ref.invalidate(dueAlertsProvider);
      if (!mounted) {
        return;
      }
      showIosToast(context, t('maintenance.plan.saved'));
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
    final Session? session = ref.watch(sessionProvider).value;
    // Xem thì ai cũng được, sửa thì cần quyền quản lý bảo trì
    final bool canEdit = session != null && session.can('Vehicles.Maintenance');
    final AsyncValue<VehicleMaintenancePlan> planValue =
        ref.watch(maintenancePlanProvider(widget.vehicleId));

    return AsyncView<VehicleMaintenancePlan>(
      value: planValue,
      onRetry: () {
        ref.invalidate(maintenancePlanProvider(widget.vehicleId));
      },
      builder: (VehicleMaintenancePlan plan) {
        fillFrom(plan);
        // Tên xe: ưu tiên tên truyền vào, không có thì tra danh sách xe đã tải
        String labelText = widget.vehicleLabel ?? '';
        if (labelText.isEmpty) {
          final List<VehicleOption>? vehicles = ref.watch(vehiclesProvider).value;
          if (vehicles != null) {
            for (final VehicleOption vehicle in vehicles) {
              if (vehicle.publicId == widget.vehicleId) {
                labelText = vehicle.plateNumber;
                break;
              }
            }
          }
        }

        final List<Widget> children = <Widget>[
          Text(
            t('maintenance.plan.header', <String, Object?>{'vehicle': labelText.isEmpty ? t('maintenance.plan.thisVehicle') : labelText.toUpperCase()}),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    FieldLabel(t('maintenance.plan.hours')),
                    _planField(hoursController, t('maintenance.plan.notTracked'), canEdit, isSaving),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    FieldLabel(t('maintenance.plan.months')),
                    _planField(monthsController, t('maintenance.plan.notTracked'), canEdit, isSaving),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    FieldLabel(t('maintenance.plan.km')),
                    _planField(kmController, t('maintenance.plan.notTracked'), canEdit, isSaving),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          NoteText(
            t('maintenance.plan.note', <String, Object?>{
              'km': formatNumber(plan.currentOdometerKm),
              'hours': formatNumber(plan.currentEngineHours),
            }),
          ),
          if (errorText != null) ...[
            const SizedBox(height: 14),
            ErrorBox(errorText!),
          ],
          if (canEdit) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: isSaving ? null : save,
              child: Text(isSaving ? t('maintenance.plan.saving') : t('maintenance.plan.save')),
            ),
          ],
        ];

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        );
      },
    );
  }

  Widget _planField(TextEditingController controller, String placeholder, bool canEdit, bool saving) {
    return TextField(
      controller: controller,
      enabled: canEdit && !saving,
      keyboardType: TextInputType.number,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: placeholder,
        hintStyle: TextStyle(fontSize: 13, color: AppColors.textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      ),
    );
  }
}