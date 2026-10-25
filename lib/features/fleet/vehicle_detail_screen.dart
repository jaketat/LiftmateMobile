// X2 chi tiết xe + X3 đổi trạng thái + X4 danh sách giấy tờ, hủy bản sai + X5 số km, giờ máy
// (theo màn N4-ChiTietXe). Không hiện phần cẩu (bảng tải, sức nâng).
import 'package:flutter/material.dart';
// Riverpod: ConsumerWidget, WidgetRef, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/labels.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../roles/role_detail_screen.dart';
import 'fleet_api.dart';
import 'shared.dart';
import 'vehicles_screen.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(doneText)));
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
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        final List<Widget> tiles = <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Đổi trạng thái xe', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ),
        ];
        for (final String choice in choices) {
          tiles.add(ListTile(
            title: Text(label(vehicleStatusLabels, choice)),
            trailing: choice == currentStatus ? const Icon(Icons.check, color: AppColors.navy) : null,
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
    }, 'Đã đổi trạng thái.');
  }

  Future<void> editOdometer(BuildContext context, WidgetRef ref, int? currentKm) async {
    final String? text = await askText(
      context,
      title: 'Cập nhật số km',
      fieldLabel: 'Số km trên đồng hồ',
      initialText: currentKm?.toString() ?? '',
      isNumber: true,
    );
    if (text == null || !context.mounted) {
      return;
    }
    await runWrite(context, ref, () {
      return setOdometer(vehicleId, num.parse(text).round());
    }, 'Đã lưu số km.');
  }

  Future<void> editEngineHours(BuildContext context, WidgetRef ref, num currentHours) async {
    final String? text = await askText(
      context,
      title: 'Cập nhật giờ máy',
      fieldLabel: 'Giờ máy (chỉ được tăng)',
      initialText: currentHours.toString(),
      isNumber: true,
    );
    if (text == null || !context.mounted) {
      return;
    }
    await runWrite(context, ref, () {
      return setEngineHours(vehicleId, num.parse(text));
    }, 'Đã lưu giờ máy.');
  }

  // "Hủy" hỏi lý do (bắt buộc) rồi gọi void. Bản ghi vẫn còn, gạch ngang.
  Future<void> voidDoc(BuildContext context, WidgetRef ref, ComplianceDoc doc) async {
    final String? reason = await askText(
      context,
      title: 'Hủy ${label(vehicleDocumentLabels, doc.documentType).toLowerCase()}',
      fieldLabel: 'Lý do',
      saveText: 'Hủy bản này',
    );
    if (reason == null || !context.mounted) {
      return;
    }
    await runWrite(context, ref, () {
      return voidVehicleDoc(vehicleId, doc.publicId, reason);
    }, 'Đã hủy giấy tờ.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<VehicleDetail> vehicleValue = ref.watch(vehicleProvider(vehicleId));
    final bool canEdit = userCan(ref, 'Vehicles.Edit');
    String title = 'Chi tiết xe';
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                statusBox(context, ref, detail, canEdit),
                for (final String warning in detail.capacityWarnings) warningBox(warning),
                const DetailSectionTitle('Thông số'),
                specsBox(detail),
                const DetailSectionTitle('Đồng hồ'),
                metersBox(context, ref, detail, canEdit),
                sectionHeader(
                  'Giấy tờ',
                  actionText: canEdit ? 'Thêm, gia hạn' : null,
                  onAction: () {
                    context.push('/fleet/$vehicleId/documents/new');
                  },
                ),
                docsBox(context, ref, canEdit),
                sectionHeader(
                  'Bảo dưỡng gần đây',
                  actionText: 'Định mức',
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
                const Text('Trạng thái', style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
                vehicleStatusPill(detail.summary.status, detail.summary.isInspectionValid),
              ],
            ),
          ),
          if (canEdit)
            OutlinedButton(
              onPressed: () {
                changeStatus(context, ref, detail.summary.status);
              },
              child: const Text('Đổi trạng thái'),
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
      child: Text(message, style: const TextStyle(fontSize: 13, color: AppColors.warnText)),
    );
  }

  Widget specsBox(VehicleDetail detail) {
    final Vehicle vehicle = detail.summary;
    String brandLine = vehicle.brandModel;
    if (vehicle.manufactureYear != null) {
      brandLine = brandLine.isEmpty ? '${vehicle.manufactureYear}' : '$brandLine · ${vehicle.manufactureYear}';
    }
    String inspectionText = 'Chưa có';
    if (vehicle.inspectionExpiryDate != null) {
      inspectionText = 'Đến ${formatDay(vehicle.inspectionExpiryDate)}';
      if (!vehicle.isInspectionValid) {
        inspectionText = 'Hết hạn ${formatDay(vehicle.inspectionExpiryDate)}';
      }
    }
    return WhiteBox(
      child: Column(
        children: [
          InfoRow('Loại xe', vehicle.vehicleType),
          if (brandLine.isNotEmpty) InfoRow('Hãng, dòng', brandLine),
          InfoRow('Tải trọng', formatKg(vehicle.maxPayloadKg)),
          InfoRow('Tự trọng', formatKg(detail.curbWeightKg)),
          if (detail.deckLengthMm != null && detail.deckWidthMm != null)
            InfoRow('Sàn', '${formatNumber(detail.deckLengthMm)} × ${formatNumber(detail.deckWidthMm)} mm'),
          if (detail.fuelConsumptionPer100Km != null)
            InfoRow('Tiêu hao dầu', '${formatNumber(detail.fuelConsumptionPer100Km)} lít/100 km'),
          InfoRow('Đăng kiểm', inspectionText),
          if (detail.inspectionCertificateNumber != null) InfoRow('Số tem', detail.inspectionCertificateNumber!),
          if (detail.insuranceExpiryDate != null) InfoRow('Bảo hiểm', 'Đến ${formatDay(detail.insuranceExpiryDate)}'),
        ],
      ),
    );
  }

  Widget meterRow(String name, String value, VoidCallback? onEdit) {
    return Row(
      children: [
        Text(name, style: const TextStyle(fontSize: 14, color: AppColors.textMuted)),
        const SizedBox(width: 12),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
        if (onEdit != null) TextButton(onPressed: onEdit, child: const Text('Cập nhật')),
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
          meterRow('Số km', kmText, canEdit && !odometerValue.isLoading
              ? () {
                  editOdometer(context, ref, km);
                }
              : null),
          meterRow('Giờ máy', '${formatNumber(detail.summary.currentEngineHours)} giờ', canEdit
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
            Expanded(child: Text(errorMessage(docsValue.error!), style: const TextStyle(color: AppColors.errorText))),
            TextButton(
              onPressed: () {
                ref.invalidate(vehicleDocsProvider(vehicleId));
              },
              child: const Text('Thử lại'),
            ),
          ],
        ),
      );
    }
    final List<ComplianceDoc>? docs = docsValue.value;
    if (docs == null) {
      return const WhiteBox(child: Center(child: CircularProgressIndicator()));
    }
    if (docs.isEmpty) {
      return const WhiteBox(child: Text('Chưa có giấy tờ nào.', style: TextStyle(color: AppColors.textMuted)));
    }
    final List<Widget> rows = <Widget>[];
    for (final ComplianceDoc doc in docs) {
      if (rows.isNotEmpty) {
        rows.add(const Divider(height: 1, color: AppColors.border));
      }
      String rule = 'chỉ nhắc';
      if (doc.blocksCapability != null) {
        rule = 'hết hạn sẽ chặn xe chạy';
      }
      String detailText = 'Đến ${formatDay(doc.effectiveUntil)} · $rule';
      if (doc.documentNumber != null && doc.documentNumber!.isNotEmpty) {
        detailText = 'Số ${doc.documentNumber} · $detailText';
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
      return const WhiteBox(child: Text('Chưa có lần bảo dưỡng nào.', style: TextStyle(color: AppColors.textMuted)));
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
                    style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
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
