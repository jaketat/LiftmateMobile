// X4: thêm giấy tờ xe hoặc gia hạn (theo màn N4-ThemGiayTo). Mỗi lần gia hạn là một dòng mới.
import 'package:flutter/cupertino.dart';
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
import '../orders/order_new_sheets.dart' show pickDateTime;

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
    return pickDateTime(
      context,
      mode: CupertinoDatePickerMode.date,
      initial: current ?? now,
      minimumDate: DateTime(now.year - 20),
      maximumDate: DateTime(now.year + 20),
    );
  }

  Future<void> pickType() async {
    final String? picked = await showIosActionSheet<String>(
      context,
      title: t('fleet.docType'),
      options: <IosSheetOption<String>>[
        for (final String type in vehicleDocTypes) IosSheetOption<String>(type, label(vehicleDocumentLabels, type)),
      ],
    );
    if (picked != null && mounted) setState(() => documentType = picked);
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

  Widget dateRow(String name, DateTime? value, ValueChanged<DateTime> onPicked) {
    return IosValueRow(
      label: name,
      value: value == null ? t('fleet.pickDate') : dateFormat.format(value),
      valueColor: value == null ? null : AppColors.text,
      onTap: isSaving
          ? null
          : () async {
              final DateTime? picked = await pickDate(value);
              if (picked != null) onPicked(picked);
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final VehicleDetail? vehicle = ref.watch(vehicleProvider(widget.vehicleId)).value;
    // Lỗi từng ô server trả về, gom lại hiện dưới nhóm
    final List<String> fieldMessages = <String>[
      for (final String field in <String>['documentType', 'documentNumber', 'issuedBy', 'issuedAt', 'effectiveUntil'])
        if (fieldError(fieldErrors, field) != null) fieldError(fieldErrors, field)!,
    ];

    return IosPage(
      title: t('documents.add'),
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Column(
            children: <Widget>[
              IosGroup(
                header: vehicle == null ? null : t('fleet.vehicleTitle', <String, Object?>{'title': vehicle.summary.title}),
                headerIcon: vehicle == null ? null : CupertinoIcons.car_detailed,
                dividerIndent: 62,
                children: <Widget>[
                  IosRow(
                    icon: CupertinoIcons.doc_text_fill,
                    title: label(vehicleDocumentLabels, documentType),
                    subtitle: t('fleet.docType'),
                    onTap: isSaving ? null : pickType,
                  ),
                ],
              ),
              IosGroup(
                children: <Widget>[
                  IosFieldRow(label: t('fleet.docNumber'), controller: numberController, placeholder: '—', enabled: !isSaving),
                  IosFieldRow(label: t('documents.issuedBy'), controller: issuedByController, placeholder: '—', enabled: !isSaving),
                ],
              ),
              IosGroup(
                footer: t('fleet.renewNote'),
                children: <Widget>[
                  dateRow(t('documents.issueDate'), issuedAt, (DateTime picked) => setState(() => issuedAt = picked)),
                  dateRow(t('fleet.effectiveUntil'), effectiveUntil, (DateTime picked) => setState(() => effectiveUntil = picked)),
                ],
              ),
              for (final String message in fieldMessages) IosErrorText(message),
              if (errorText != null && fieldMessages.isEmpty) IosErrorText(errorText!),
              IosFormButton(
                label: isSaving ? t('common.saving') : t('documents.save'),
                busy: isSaving,
                onPressed: save,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
