// X2 chi tiết xe + X3 đổi trạng thái + X4 danh sách giấy tờ, hủy bản sai + X5 số km, giờ máy
// (theo màn N4-ChiTietXe). Không hiện phần cẩu (bảng tải, sức nâng).
import 'package:flutter/cupertino.dart';
// Riverpod: ConsumerWidget, WidgetRef, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/labels.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import 'fleet_api.dart';
import 'shared.dart';
import 'vehicles_screen.dart';
import '../../core/widgets/ios.dart';

class VehicleDetailScreen extends ConsumerWidget {
  final String vehicleId;

  const VehicleDetailScreen({super.key, required this.vehicleId});

  // Ghi xong thì đổ các hộp của xe này để tải lại
  void reloadVehicle(WidgetRef ref) {
    ref.invalidate(vehicleProvider(vehicleId));
    ref.invalidate(vehicleOdometerProvider(vehicleId));
    ref.invalidate(vehicleDocsProvider(vehicleId));
  }

  // Chạy một lệnh ghi: lỗi thì hiện câu của server ở đáy màn, xong thì tải lại xe
  Future<void> runWrite(BuildContext context, WidgetRef ref, Future<void> Function() write, String doneText) async {
    try {
      await write();
      reloadVehicle(ref);
      if (context.mounted) {
        showIosToast(context, doneText);
      }
    } catch (error) {
      if (context.mounted) {
        showErrorSnackBar(context, error);
      }
    }
  }

  // X3: chọn trạng thái mới. Xe hết đăng kiểm chọn Sẵn sàng thì server trả 422, hiện câu lỗi.
  Future<void> changeStatus(BuildContext context, WidgetRef ref, String currentStatus) async {
    const List<String> choices = <String>['Available', 'UnderMaintenance', 'Suspended'];
    final String? picked = await showIosActionSheet<String>(
      context,
      title: t('fleet.changeStatusTitle'),
      options: <IosSheetOption<String>>[
        for (final String choice in choices)
          if (choice != currentStatus) IosSheetOption<String>(choice, label(vehicleStatusLabels, choice), destructive: choice == 'Suspended'),
      ],
    );
    if (picked == null || picked == currentStatus || !context.mounted) {
      return;
    }
    await runWrite(context, ref, () {
      return updateVehicleStatus(vehicleId, picked);
    }, t('fleet.statusChanged'));
  }

  Future<void> editOdometer(BuildContext context, WidgetRef ref, int? currentKm) async {
    final String? text = await askText(
      context,
      title: t('fleet.odometerTitle'),
      fieldLabel: t('fleet.odometerField'),
      initialText: currentKm?.toString() ?? '',
      isNumber: true,
    );
    if (text == null || !context.mounted) {
      return;
    }
    await runWrite(context, ref, () {
      return setOdometer(vehicleId, num.parse(text).round());
    }, t('fleet.odometerSaved'));
  }

  Future<void> editEngineHours(BuildContext context, WidgetRef ref, num currentHours) async {
    final String? text = await askText(
      context,
      title: t('fleet.engineHoursTitle'),
      fieldLabel: t('fleet.engineHoursField'),
      // Số giờ tròn thì không hiện ".0"
      initialText: currentHours == currentHours.roundToDouble() ? currentHours.toStringAsFixed(0) : currentHours.toString(),
      isNumber: true,
    );
    if (text == null || !context.mounted) {
      return;
    }
    await runWrite(context, ref, () {
      return setEngineHours(vehicleId, num.parse(text));
    }, t('fleet.engineHoursSaved'));
  }

  // "Hủy" hỏi lý do (bắt buộc) rồi gọi void. Bản ghi vẫn còn, gạch ngang.
  Future<void> voidDoc(BuildContext context, WidgetRef ref, ComplianceDoc doc) async {
    final String typeName = label(vehicleDocumentLabels, doc.documentType);
    final bool? confirmed = await showIosActionSheet<bool>(
      context,
      title: typeName,
      options: <IosSheetOption<bool>>[IosSheetOption<bool>(true, t('fleet.voidThis'), destructive: true)],
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    final String? reason = await askText(
      context,
      title: t('fleet.voidTitle', <String, Object?>{'type': label(vehicleDocumentLabels, doc.documentType).toLowerCase()}),
      fieldLabel: t('fleet.reason'),
      saveText: t('fleet.voidThis'),
    );
    if (reason == null || !context.mounted) {
      return;
    }
    await runWrite(context, ref, () {
      return voidVehicleDoc(vehicleId, doc.publicId, reason);
    }, t('fleet.voidDone'));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<VehicleDetail> vehicleValue = ref.watch(vehicleProvider(vehicleId));
    final VehicleDetail? detail = vehicleValue.value;
    if (detail == null) {
      return IosPage(
        title: t('fleet.detailTitle'),
        slivers: <Widget>[
          SliverFillRemaining(
            hasScrollBody: false,
            child: AsyncView<VehicleDetail>(
              value: vehicleValue,
              onRetry: () => reloadVehicle(ref),
              builder: (VehicleDetail _) => const SizedBox.shrink(),
            ),
          ),
        ],
      );
    }
    final bool canEdit = userCan(ref, 'Vehicles.Edit');
    return IosPage(
      title: detail.summary.title,
      onRefresh: () {
        ref.invalidate(vehicleOdometerProvider(vehicleId));
        ref.invalidate(vehicleDocsProvider(vehicleId));
        return ref.refresh(vehicleProvider(vehicleId).future);
      },
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Column(
            children: <Widget>[
              statusGroup(context, ref, detail, canEdit),
              if (detail.capacityWarnings.isNotEmpty) warningGroup(detail.capacityWarnings),
              specsGroup(detail),
              metersGroup(context, ref, detail, canEdit),
              docsGroup(context, ref, canEdit),
              maintenanceGroup(context, detail),
            ],
          ),
        ),
      ],
    );
  }

  // Nút chữ nhỏ cuối dòng tiêu đề nhóm (vd "Thêm, gia hạn")
  Widget headerButton(String text, VoidCallback onPressed) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 28),
      onPressed: onPressed,
      child: Text(text, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: IosColors.blue)),
    );
  }

  Widget statusGroup(BuildContext context, WidgetRef ref, VehicleDetail detail, bool canEdit) {
    final Vehicle vehicle = detail.summary;
    final String subtitle = <String>[
      vehicle.vehicleType,
      if (vehicle.brandModel.isNotEmpty) vehicle.brandModel,
    ].join(' · ');
    return IosGroup(
      dividerIndent: 62,
      children: <Widget>[
        IosRow(
          icon: CupertinoIcons.car_detailed,
          iconColor: vehicle.isInspectionValid ? AppColors.navy : IosColors.red,
          title: t('fleet.status'),
          subtitle: subtitle,
          trailing: vehicleStatusPill(vehicle.status, vehicle.isInspectionValid),
          onTap: canEdit ? () => changeStatus(context, ref, vehicle.status) : null,
        ),
      ],
    );
  }

  Widget warningGroup(List<String> warnings) {
    return IosGroup(
      dividerIndent: 62,
      children: <Widget>[
        for (final String warning in warnings)
          IosRow(
            icon: CupertinoIcons.exclamationmark_triangle_fill,
            iconColor: IosColors.orange,
            titleWidget: Text(warning, style: TextStyle(fontSize: 15, height: 1.35, color: AppColors.warnText)),
            title: warning,
            chevron: false,
          ),
      ],
    );
  }

  Widget specsGroup(VehicleDetail detail) {
    final Vehicle vehicle = detail.summary;
    String brandLine = vehicle.brandModel;
    if (vehicle.manufactureYear != null) {
      brandLine = brandLine.isEmpty ? '${vehicle.manufactureYear}' : '$brandLine · ${vehicle.manufactureYear}';
    }
    String inspectionText = t('fleet.none');
    if (vehicle.inspectionExpiryDate != null) {
      inspectionText = t('fleet.until', <String, Object?>{'date': formatDay(vehicle.inspectionExpiryDate)});
      if (!vehicle.isInspectionValid) {
        inspectionText = t('fleet.expiredOn', <String, Object?>{'date': formatDay(vehicle.inspectionExpiryDate)});
      }
    }
    return IosGroup(
      header: t('fleet.specs'),
      headerIcon: CupertinoIcons.doc_plaintext,
      children: <Widget>[
        IosValueRow(label: t('fleet.vehicleType'), value: vehicle.vehicleType),
        if (brandLine.isNotEmpty) IosValueRow(label: t('fleet.brandModel'), value: brandLine),
        IosValueRow(label: t('fleet.payload'), value: formatKg(vehicle.maxPayloadKg)),
        IosValueRow(label: t('fleet.curbWeight'), value: formatKg(detail.curbWeightKg)),
        if (detail.deckLengthMm != null && detail.deckWidthMm != null)
          IosValueRow(label: t('fleet.deck'), value: '${formatNumber(detail.deckLengthMm)} × ${formatNumber(detail.deckWidthMm)} mm'),
        if (detail.fuelConsumptionPer100Km != null)
          IosValueRow(
            label: t('fleet.fuelUse'),
            value: t('fleet.fuelValue', <String, Object?>{'value': formatNumber(detail.fuelConsumptionPer100Km)}),
          ),
        IosValueRow(
          label: t('fleet.inspection'),
          value: inspectionText,
          valueColor: vehicle.isInspectionValid ? null : AppColors.errorText,
        ),
        if (detail.inspectionCertificateNumber != null)
          IosValueRow(label: t('fleet.stickerNo'), value: detail.inspectionCertificateNumber!),
        if (detail.insuranceExpiryDate != null)
          IosValueRow(
            label: t('fleet.insurance'),
            value: t('fleet.until', <String, Object?>{'date': formatDay(detail.insuranceExpiryDate)}),
          ),
      ],
    );
  }

  Widget metersGroup(BuildContext context, WidgetRef ref, VehicleDetail detail, bool canEdit) {
    // Số km lấy riêng từ định mức bảo trì: đang tải hoặc lỗi thì hiện "—", phần còn lại vẫn xem được
    final AsyncValue<int?> odometerValue = ref.watch(vehicleOdometerProvider(vehicleId));
    final int? km = odometerValue.value;
    return IosGroup(
      header: t('fleet.meters'),
      headerIcon: CupertinoIcons.speedometer,
      footer: canEdit ? t('fleet.metersHint') : null,
      children: <Widget>[
        IosValueRow(
          label: t('fleet.odometer'),
          value: km == null ? '—' : '${formatNumber(km)} km',
          onTap: canEdit && !odometerValue.isLoading ? () => editOdometer(context, ref, km) : null,
        ),
        IosValueRow(
          label: t('fleet.engineHours'),
          value: t('fleet.hoursValue', <String, Object?>{'value': formatNumber(detail.summary.currentEngineHours)}),
          onTap: canEdit ? () => editEngineHours(context, ref, detail.summary.currentEngineHours) : null,
        ),
      ],
    );
  }

  Widget docsGroup(BuildContext context, WidgetRef ref, bool canEdit) {
    final AsyncValue<List<ComplianceDoc>> docsValue = ref.watch(vehicleDocsProvider(vehicleId));
    final List<ComplianceDoc>? docs = docsValue.value;
    final List<Widget> rows = <Widget>[];
    if (docsValue.hasError && !docsValue.isLoading) {
      rows.add(IosRow(
        icon: CupertinoIcons.exclamationmark_circle,
        iconColor: IosColors.red,
        title: errorMessage(docsValue.error!),
        subtitle: t('common.retry'),
        onTap: () => ref.invalidate(vehicleDocsProvider(vehicleId)),
      ));
    } else if (docs == null) {
      rows.add(const Padding(padding: EdgeInsets.all(16), child: Center(child: CupertinoActivityIndicator())));
    } else if (docs.isEmpty) {
      rows.add(IosRow(icon: CupertinoIcons.doc, iconColor: IosColors.secondaryLabel, title: t('fleet.noDocs'), chevron: false));
    } else {
      for (final ComplianceDoc doc in docs) {
        rows.add(_DocRow(
          doc: doc,
          typeName: label(vehicleDocumentLabels, doc.documentType),
          detail: docDetailText(doc),
          onVoid: canEdit ? () => voidDoc(context, ref, doc) : null,
        ));
      }
    }
    return IosGroup(
      header: t('documents.title'),
      headerIcon: CupertinoIcons.doc_on_doc_fill,
      headerTrailing: canEdit ? headerButton(t('fleet.addRenew'), () => context.push('/fleet/$vehicleId/documents/new')) : null,
      dividerIndent: 62,
      children: rows,
    );
  }

  String docDetailText(ComplianceDoc doc) {
    final String rule = doc.blocksCapability != null ? t('fleet.ruleBlocks') : t('fleet.ruleReminder');
    if (doc.documentNumber != null && doc.documentNumber!.isNotEmpty) {
      return t('fleet.docDetailNumber', <String, Object?>{'number': doc.documentNumber, 'date': formatDay(doc.effectiveUntil), 'rule': rule});
    }
    return t('fleet.docDetail', <String, Object?>{'date': formatDay(doc.effectiveUntil), 'rule': rule});
  }

  Widget maintenanceGroup(BuildContext context, VehicleDetail detail) {
    return IosGroup(
      header: t('fleet.recentMaintenance'),
      headerIcon: CupertinoIcons.wrench_fill,
      // Màn định mức bảo trì của người 5 (M5)
      headerTrailing: headerButton(t('fleet.maintenancePlan'), () => context.push('/maintenance/plan/$vehicleId')),
      dividerIndent: 62,
      children: <Widget>[
        if (detail.recentMaintenance.isEmpty)
          IosRow(icon: CupertinoIcons.wrench, iconColor: IosColors.secondaryLabel, title: t('fleet.noMaintenance'), chevron: false),
        for (final MaintenanceItem item in detail.recentMaintenance)
          IosRow(
            icon: CupertinoIcons.wrench_fill,
            iconColor: item.kind == 'Repair' ? IosColors.orange : AppColors.navy,
            title: item.title,
            subtitle: '${label(maintenanceKindLabels, item.kind)} · ${label(maintenanceStatusLabels, item.status)}',
            value: formatDay(item.completedOn ?? item.startDate),
            chevron: false,
          ),
      ],
    );
  }
}

/// Một giấy tờ: tên, số và hạn, nhãn còn hạn. Bấm vào để hủy bản sai (nếu được). Bản đã hủy: gạch ngang + lý do.
class _DocRow extends StatelessWidget {
  final ComplianceDoc doc;
  final String typeName;
  final String detail;
  final VoidCallback? onVoid;

  const _DocRow({required this.doc, required this.typeName, required this.detail, this.onVoid});

  @override
  Widget build(BuildContext context) {
    final bool voided = doc.isVoided;
    return IosRow(
      icon: CupertinoIcons.doc_text_fill,
      iconColor: voided ? IosColors.secondaryLabel : AppColors.navy,
      title: typeName,
      titleWidget: Text(
        typeName,
        style: TextStyle(
          fontSize: 17,
          color: voided ? AppColors.textMuted : AppColors.text,
          decoration: voided ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: voided ? (doc.voidReason ?? t('fleet.voided')) : detail,
      trailing: voided ? IosPill(t('fleet.voided'), color: IosColors.secondaryLabel) : daysPill(daysUntil(doc.effectiveUntil)),
      onTap: voided ? null : onVoid,
      chevron: false,
    );
  }
}
