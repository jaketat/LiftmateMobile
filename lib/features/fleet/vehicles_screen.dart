// X1: danh sách xe, tìm biển số, lọc loại xe và trạng thái (theo màn N4-DanhSachXe)
import 'package:flutter/material.dart';
// go_router: context.push
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/labels.dart';
import '../../core/theme.dart';
import 'fleet_api.dart';
import 'shared.dart';

class VehiclesScreen extends StatefulWidget {
  VehiclesScreen({super.key});

  @override
  State<VehiclesScreen> createState() {
    return _VehiclesScreenState();
  }
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  String search = '';
  String? baseType;
  String? status;

  @override
  Widget build(BuildContext context) {
    final Map<String?, String> typeOptions = <String?, String>{null: t('fleet.all'), ...vehicleBaseTypeLabels};
    final Map<String?, String> statusOptions = <String?, String>{null: t('fleet.anyStatus'), ...vehicleStatusLabels};

    return Scaffold(
      appBar: AppBar(title: Text(t('tabs.fleet'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchField(
              hint: t('fleet.searchHint'),
              onChanged: (String text) {
                setState(() {
                  search = text;
                });
              },
            ),
          ),
          FilterChips(
            options: typeOptions,
            selected: baseType,
            onSelected: (String? value) {
              setState(() {
                baseType = value;
              });
            },
          ),
          const SizedBox(height: 6),
          FilterChips(
            options: statusOptions,
            selected: status,
            onSelected: (String? value) {
              setState(() {
                status = value;
              });
            },
          ),
          const SizedBox(height: 6),
          Expanded(
            // Đổi bộ lọc → key đổi → danh sách tải lại từ trang 1
            child: PagedList<Vehicle>(
              key: ValueKey<String>('$search|$baseType|$status'),
              fetchPage: (int pageNumber) {
                return fetchVehicles(pageNumber, search, baseType, status);
              },
              emptyText: t('fleet.empty'),
              itemBuilder: (Vehicle vehicle) {
                return VehicleCard(vehicle: vehicle);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Nhãn trạng thái xe. Hết đăng kiểm thì nhãn đỏ "Hết đăng kiểm" thay cho trạng thái.
Pill vehicleStatusPill(String status, bool isInspectionValid) {
  if (!isInspectionValid) {
    return Pill.error(t('fleet.inspectionExpired'));
  }
  final String text = label(vehicleStatusLabels, status);
  switch (status) {
    case 'Available':
      return Pill.ok(text);
    case 'UnderMaintenance':
      return Pill.warn(text);
    case 'Suspended':
      return Pill.error(text);
    default:
      return Pill.navy(text);
  }
}

class VehicleCard extends StatelessWidget {
  final Vehicle vehicle;

  const VehicleCard({super.key, required this.vehicle});

  @override
  Widget build(BuildContext context) {
    final List<String> parts = <String>[vehicle.vehicleType];
    if (vehicle.brandModel.isNotEmpty) {
      parts.add(vehicle.brandModel);
    }
    if (vehicle.maxPayloadKg > 0) {
      parts.add(t('fleet.payloadPart', <String, Object?>{'weight': formatKg(vehicle.maxPayloadKg)}));
    }

    Widget inspectionLine = const SizedBox.shrink();
    if (!vehicle.isInspectionValid) {
      String text = t('fleet.inspectionExpiredNoAssign');
      if (vehicle.inspectionExpiryDate != null) {
        text = t('fleet.expiredNoAssign', <String, Object?>{'date': formatDay(vehicle.inspectionExpiryDate)});
      }
      inspectionLine = Text(
        text,
        style: TextStyle(fontSize: 13, color: AppColors.errorText, fontWeight: FontWeight.w600),
      );
    } else if (vehicle.inspectionExpiryDate != null) {
      inspectionLine = Text(
        t('fleet.inspectionUntil', <String, Object?>{'date': formatDay(vehicle.inspectionExpiryDate)}),
        style: TextStyle(fontSize: 13, color: AppColors.textMuted),
      );
    }

    return TapCard(
      onTap: () {
        context.push('/fleet/${vehicle.publicId}');
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(vehicle.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              vehicleStatusPill(vehicle.status, vehicle.isInspectionValid),
            ],
          ),
          const SizedBox(height: 4),
          Text(parts.join(' · '), style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 2),
          inspectionLine,
        ],
      ),
    );
  }
}
