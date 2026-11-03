// X2 chi tiết xe + X3 đổi trạng thái + X4 danh sách giấy tờ, hủy bản sai + X5 số km, giờ máy
// (theo màn N4-ChiTietXe). Không hiện phần cẩu (bảng tải, sức nâng).
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
// Riverpod: ConsumerWidget, WidgetRef, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/labels.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../roles/role_detail_screen.dart';
import 'fleet_api.dart';
import 'shared.dart';
import 'vehicles_screen.dart';
import '../../core/widgets/ios.dart';
import '../../core/widgets/page_transition.dart';

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
    final String? picked = await showModalBottomSheet<String>(
      useRootNavigator: true,
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        final List<Widget> tiles = <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(t('fleet.changeStatusTitle'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ),
        ];
        for (final String choice in choices) {
          tiles.add(ListTile(
            title: Text(label(vehicleStatusLabels, choice)),
            trailing: choice == currentStatus ? Icon(Icons.check, color: AppColors.navy) : null,
            onTap: () {
              Navigator.of(sheetContext).pop(choice);
            },
          ));
        }
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: tiles),
        );
      },
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
      initialText: currentHours.toString(),
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
    final bool canEdit = userCan(ref, 'Vehicles.Edit');
    String title = t('fleet.detailTitle');
    if (vehicleValue.value != null) {
      title = vehicleValue.value!.summary.title;
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: AsyncView<VehicleDetail>(
        value: vehicleValue,
        onRetry: () {
          reloadVehicle(ref);
        },
        builder: (VehicleDetail detail) {
          return RefreshIndicator(
            onRefresh: () {
              ref.invalidate(vehicleOdometerProvider(vehicleId));
              ref.invalidate(vehicleDocsProvider(vehicleId));
              return ref.refresh(vehicleProvider(vehicleId).future);
            },
            child: ListView(
              padding: withTabBarInset(context, const EdgeInsets.fromLTRB(16, 8, 16, 32)),
              children: [
                statusBox(context, ref, detail, canEdit),
                for (final String warning in detail.capacityWarnings) warningBox(warning),
                DetailSectionTitle(t('fleet.specs')),
                specsBox(detail),
                DetailSectionTitle(t('fleet.meters')),
                metersBox(context, ref, detail, canEdit),
                sectionHeader(
                  t('documents.title'),
                  actionText: canEdit ? t('fleet.addRenew') : null,
                  onAction: () {
                    context.push('/fleet/$vehicleId/documents/new');
                  },
                ),
                docsBox(context, ref, canEdit),
                sectionHeader(
                  t('fleet.recentMaintenance'),
                  actionText: t('fleet.maintenancePlan'),
                  onAction: () {
                    // Màn định mức bảo trì của người 5 (M5)
                    context.push('/maintenance/plan/$vehicleId');
                  },
                ),
                maintenanceBox(detail),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget statusBox(BuildContext context, WidgetRef ref, VehicleDetail detail, bool canEdit) {
    return WhiteBox(
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(t('fleet.status'), style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
                vehicleStatusPill(detail.summary.status, detail.summary.isInspectionValid),
              ],
            ),
          ),
          if (canEdit)
            OutlinedButton(
              onPressed: () {
                changeStatus(context, ref, detail.summary.status);
              },
              child: Text(t('fleet.changeStatus')),
            ),
        ],
      ),
    );
  }

  Widget warningBox(String message) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.warnBackground, borderRadius: BorderRadius.circular(12)),
      child: Text(message, style: TextStyle(fontSize: 13, color: AppColors.warnText)),
    );
  }

  Widget specsBox(VehicleDetail detail) {
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
    return WhiteBox(
      child: Column(
        children: [
          InfoRow(t('fleet.vehicleType'), vehicle.vehicleType),
          if (brandLine.isNotEmpty) InfoRow(t('fleet.brandModel'), brandLine),
          InfoRow(t('fleet.payload'), formatKg(vehicle.maxPayloadKg)),
          InfoRow(t('fleet.curbWeight'), formatKg(detail.curbWeightKg)),
          if (detail.deckLengthMm != null && detail.deckWidthMm != null)
            InfoRow(t('fleet.deck'), '${formatNumber(detail.deckLengthMm)} × ${formatNumber(detail.deckWidthMm)} mm'),
          if (detail.fuelConsumptionPer100Km != null)
            InfoRow(t('fleet.fuelUse'), t('fleet.fuelValue', <String, Object?>{'value': formatNumber(detail.fuelConsumptionPer100Km)})),
          InfoRow(t('fleet.inspection'), inspectionText),
          if (detail.inspectionCertificateNumber != null) InfoRow(t('fleet.stickerNo'), detail.inspectionCertificateNumber!),
          if (detail.insuranceExpiryDate != null) InfoRow(t('fleet.insurance'), t('fleet.until', <String, Object?>{'date': formatDay(detail.insuranceExpiryDate)})),
        ],
      ),
    );
  }

  Widget meterRow(String name, String value, VoidCallback? onEdit) {
    return Row(
      children: [
        Text(name, style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
        const SizedBox(width: 12),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
        if (onEdit != null) TextButton(onPressed: onEdit, child: Text(t('fleet.update'))),
      ],
    );
  }

  Widget metersBox(BuildContext context, WidgetRef ref, VehicleDetail detail, bool canEdit) {
    // Số km lấy riêng từ định mức bảo trì: đang tải hoặc lỗi thì hiện "—", phần còn lại vẫn xem được
    final AsyncValue<int?> odometerValue = ref.watch(vehicleOdometerProvider(vehicleId));
    final int? km = odometerValue.value;
    String kmText = '—';
    if (km != null) {
      kmText = '${formatNumber(km)} km';
    }
    return WhiteBox(
      child: Column(
        children: [
          meterRow(t('fleet.odometer'), kmText, canEdit && !odometerValue.isLoading
              ? () {
                  editOdometer(context, ref, km);
                }
              : null),
          meterRow(t('fleet.engineHours'), t('fleet.hoursValue', <String, Object?>{'value': formatNumber(detail.summary.currentEngineHours)}), canEdit
              ? () {
                  editEngineHours(context, ref, detail.summary.currentEngineHours);
                }
              : null),
        ],
      ),
    );
  }

  Widget docsBox(BuildContext context, WidgetRef ref, bool canEdit) {
    final AsyncValue<List<ComplianceDoc>> docsValue = ref.watch(vehicleDocsProvider(vehicleId));
    if (docsValue.hasError && !docsValue.isLoading) {
      return WhiteBox(
        child: Row(
          children: [
            Expanded(child: Text(errorMessage(docsValue.error!), style: TextStyle(color: AppColors.errorText))),
            TextButton(
              onPressed: () {
                ref.invalidate(vehicleDocsProvider(vehicleId));
              },
              child: Text(t('common.retry')),
            ),
          ],
        ),
      );
    }
    final List<ComplianceDoc>? docs = docsValue.value;
    if (docs == null) {
      return const WhiteBox(child: Center(child: CupertinoActivityIndicator(radius: 14)));
    }
    if (docs.isEmpty) {
      return WhiteBox(child: Text(t('fleet.noDocs'), style: TextStyle(color: AppColors.textMuted)));
    }
    final List<Widget> rows = <Widget>[];
    for (final ComplianceDoc doc in docs) {
      if (rows.isNotEmpty) {
        rows.add(Divider(height: 1, color: AppColors.border));
      }
      String rule = t('fleet.ruleReminder');
      if (doc.blocksCapability != null) {
        rule = t('fleet.ruleBlocks');
      }
      String detailText = t('fleet.docDetail', <String, Object?>{'date': formatDay(doc.effectiveUntil), 'rule': rule});
      if (doc.documentNumber != null && doc.documentNumber!.isNotEmpty) {
        detailText = t('fleet.docDetailNumber', <String, Object?>{'number': doc.documentNumber, 'date': formatDay(doc.effectiveUntil), 'rule': rule});
      }
      rows.add(DocTile(
        doc: doc,
        typeName: label(vehicleDocumentLabels, doc.documentType),
        detail: detailText,
        onVoid: canEdit
            ? () {
                voidDoc(context, ref, doc);
              }
            : null,
      ));
    }
    return WhiteBox(child: Column(children: rows));
  }

  Widget maintenanceBox(VehicleDetail detail) {
    if (detail.recentMaintenance.isEmpty) {
      return WhiteBox(child: Text(t('fleet.noMaintenance'), style: TextStyle(color: AppColors.textMuted)));
    }
    final List<Widget> rows = <Widget>[];
    for (final MaintenanceItem item in detail.recentMaintenance) {
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(
                    '${label(maintenanceKindLabels, item.kind)} · ${label(maintenanceStatusLabels, item.status)}',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            Text(formatDay(item.completedOn ?? item.startDate), style: const TextStyle(fontSize: 13)),
          ],
        ),
      ));
    }
    return WhiteBox(child: Column(children: rows));
  }
}
