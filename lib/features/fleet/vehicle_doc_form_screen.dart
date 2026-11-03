// X4: thêm giấy tờ xe hoặc gia hạn (theo màn N4-ThemGiayTo). Mỗi lần gia hạn là một dòng mới.
import 'package:flutter/material.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/call.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/labels.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import 'fleet_api.dart';
import 'shared.dart';
import '../../core/widgets/ios.dart';
import '../../core/widgets/page_transition.dart';

// Loại giấy app cho chọn (doc mục 3.3)
const List<String> vehicleDocTypes = <String>[
  'VehicleInspection',
  'TrailerInspection',
  'VehicleRegistration',
  'CompulsoryInsurance',
  'VoluntaryInsurance',
];

class VehicleDocFormScreen extends ConsumerStatefulWidget {
  final String vehicleId;

  const VehicleDocFormScreen({super.key, required this.vehicleId});

  @override
  ConsumerState<VehicleDocFormScreen> createState() {
    return _VehicleDocFormScreenState();
  }
}

class _VehicleDocFormScreenState extends ConsumerState<VehicleDocFormScreen> {
  final TextEditingController numberController = TextEditingController();
  final TextEditingController issuedByController = TextEditingController();
  String documentType = vehicleDocTypes.first;
  DateTime? issuedAt;
  DateTime? effectiveUntil;
  bool isSaving = false;
  String? errorText;
  Map<String, String> fieldErrors = <String, String>{};

  @override
  void dispose() {
    numberController.dispose();
    issuedByController.dispose();
    super.dispose();
  }

  Future<DateTime?> pickDate(DateTime? current) {
    final DateTime now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 20),
    );
  }

  Future<void> save() async {
    if (effectiveUntil == null) {
      setState(() {
        fieldErrors = <String, String>{'effectiveUntil': t('fleet.pickEffectiveUntil')};
      });
      return;
    }
    setState(() {
      isSaving = true;
      errorText = null;
      fieldErrors = <String, String>{};
    });
    try {
      await addVehicleDoc(widget.vehicleId, <String, dynamic>{
        'documentType': documentType,
        'documentNumber': numberController.text.trim().isEmpty ? null : numberController.text.trim(),
        'issuedBy': issuedByController.text.trim().isEmpty ? null : issuedByController.text.trim(),
        'issuedAt': issuedAt?.toIso8601String(),
        'effectiveUntil': effectiveUntil!.toIso8601String(),
      });
      // Hạn mới hiện ngay ở chi tiết xe
      ref.invalidate(vehicleDocsProvider(widget.vehicleId));
      ref.invalidate(vehicleProvider(widget.vehicleId));
      if (!mounted) {
        return;
      }
      showIosToast(context, t('fleet.docSaved'));
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        isSaving = false;
        errorText = errorMessage(error);
        if (error is ApiException) {
          fieldErrors = error.fieldErrors;
        }
      });
    }
  }

  Widget dateField(String name, DateTime? value, String field, ValueChanged<DateTime> onPicked) {
    return InkWell(
      onTap: () async {
        final DateTime? picked = await pickDate(value);
        if (picked != null) {
          onPicked(picked);
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: name,
          errorText: fieldError(fieldErrors, field),
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 20),
        ),
        child: Text(value == null ? t('fleet.pickDate') : dateFormat.format(value)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final VehicleDetail? vehicle = ref.watch(vehicleProvider(widget.vehicleId)).value;
    final List<DropdownMenuItem<String>> typeItems = <DropdownMenuItem<String>>[];
    for (final String type in vehicleDocTypes) {
      typeItems.add(DropdownMenuItem<String>(value: type, child: Text(label(vehicleDocumentLabels, type))));
    }

    return Scaffold(
      appBar: AppBar(title: Text(t('documents.add'))),
      body: ListView(
        padding: withTabBarInset(context, const EdgeInsets.all(16)),
        children: [
          if (vehicle != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(t('fleet.vehicleTitle', <String, Object?>{'title': vehicle.summary.title}), style: TextStyle(color: AppColors.textMuted)),
            ),
          DropdownButtonFormField<String>(
            initialValue: documentType,
            items: typeItems,
            decoration: InputDecoration(labelText: t('fleet.docType'), errorText: fieldError(fieldErrors, 'documentType')),
            onChanged: (String? value) {
              if (value != null) {
                setState(() {
                  documentType = value;
                });
              }
            },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: numberController,
            decoration: InputDecoration(labelText: t('fleet.docNumber'), errorText: fieldError(fieldErrors, 'documentNumber')),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: issuedByController,
            decoration: InputDecoration(labelText: t('documents.issuedBy'), errorText: fieldError(fieldErrors, 'issuedBy')),
          ),
          const SizedBox(height: 14),
          dateField(t('documents.issueDate'), issuedAt, 'issuedAt', (DateTime picked) {
            setState(() {
              issuedAt = picked;
            });
          }),
          const SizedBox(height: 14),
          dateField(t('fleet.effectiveUntil'), effectiveUntil, 'effectiveUntil', (DateTime picked) {
            setState(() {
              effectiveUntil = picked;
            });
          }),
          const SizedBox(height: 14),
          Text(
            t('fleet.renewNote'),
            style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.5),
          ),
          if (errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(errorText!, style: TextStyle(color: AppColors.errorText)),
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: isSaving ? null : save,
            child: Text(isSaving ? t('common.saving') : t('documents.save')),
          ),
        ],
      ),
    );
  }
}
