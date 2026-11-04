// X1: danh sách xe, tìm biển số, lọc loại xe và trạng thái (theo màn N4-DanhSachXe)
import 'dart:async';

import 'package:flutter/cupertino.dart';
// go_router: context.push
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/labels.dart';
import '../../core/theme.dart';
import '../../core/widgets/ios.dart';
import '../../core/widgets/ios_paged_sliver.dart';
import 'fleet_api.dart';
import 'shared.dart';

class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({super.key});

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  final GlobalKey<IosPagedSliverState<Vehicle>> listKey = GlobalKey<IosPagedSliverState<Vehicle>>();
  String search = '';
  String? baseType;
  String? status;
  // Gõ xong 0,35 giây mới tìm, đỡ gọi API mỗi phím
  Timer? searchDebounce;

  @override
  void dispose() {
    searchDebounce?.cancel();
    super.dispose();
  }

  void onSearch(String text) {
    searchDebounce?.cancel();
    searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (text.trim() != search) setState(() => search = text.trim());
    });
  }

  Future<void> openVehicle(Vehicle vehicle) async {
    await context.push('/fleet/${vehicle.publicId}');
    // Có thể vừa đổi trạng thái hoặc thêm giấy tờ trong màn chi tiết
    await listKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return IosPage(
      title: t('tabs.fleet'),
      inlineTitle: true,
      onRefresh: () async => listKey.currentState?.reload(),
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: CupertinoSearchTextField(
              placeholder: t('fleet.searchHint'),
              style: TextStyle(color: AppColors.text),
              onChanged: onSearch,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: IosFilterBar<String>(
            options: <String?, String>{null: t('fleet.all'), ...vehicleBaseTypeLabels},
            selected: baseType,
            onSelected: (String? value) => setState(() => baseType = value),
          ),
        ),
        SliverToBoxAdapter(
          child: IosFilterBar<String>(
            options: <String?, String>{null: t('fleet.anyStatus'), ...vehicleStatusLabels},
            selected: status,
            onSelected: (String? value) => setState(() => status = value),
          ),
        ),
        IosPagedSliver<Vehicle>(
          key: listKey,
          query: (search, baseType, status),
          fetchPage: (int pageNumber) => fetchVehicles(pageNumber, search, baseType, status),
          emptyText: t('fleet.empty'),
          emptyIcon: CupertinoIcons.car_detailed,
          itemBuilder: (Vehicle vehicle) => VehicleCard(vehicle: vehicle, onTap: () => openVehicle(vehicle)),
        ),
      ],
    );
  }
}

// Nhãn trạng thái xe. Hết đăng kiểm thì nhãn đỏ "Hết đăng kiểm" thay cho trạng thái.
Widget vehicleStatusPill(String status, bool isInspectionValid) {
  if (!isInspectionValid) return IosPill(t('fleet.inspectionExpired'), color: IosColors.red);
  final String text = label(vehicleStatusLabels, status);
  switch (status) {
    case 'Available':
      return IosPill(text, color: IosColors.green);
    case 'UnderMaintenance':
      return IosPill(text, color: IosColors.orange);
    case 'Suspended':
      return IosPill(text, color: IosColors.red);
    default:
      return IosPill(text, color: AppColors.navy);
  }
}

class VehicleCard extends StatelessWidget {
  final Vehicle vehicle;
  final VoidCallback onTap;

  const VehicleCard({super.key, required this.vehicle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final List<String> parts = <String>[vehicle.vehicleType];
    if (vehicle.brandModel.isNotEmpty) parts.add(vehicle.brandModel);
    if (vehicle.maxPayloadKg > 0) parts.add(t('fleet.payloadPart', <String, Object?>{'weight': formatKg(vehicle.maxPayloadKg)}));

    String? inspectionText;
    if (!vehicle.isInspectionValid) {
      inspectionText = vehicle.inspectionExpiryDate == null
          ? t('fleet.inspectionExpiredNoAssign')
          : t('fleet.expiredNoAssign', <String, Object?>{'date': formatDay(vehicle.inspectionExpiryDate)});
    } else if (vehicle.inspectionExpiryDate != null) {
      inspectionText = t('fleet.inspectionUntil', <String, Object?>{'date': formatDay(vehicle.inspectionExpiryDate)});
    }

    return IosCard(
      onTap: onTap,
      child: Row(
        children: <Widget>[
          IosIconBadge(
            icon: CupertinoIcons.car_detailed,
            color: vehicle.isInspectionValid ? AppColors.navy : IosColors.red,
            size: 40,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(vehicle.title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text)),
                    ),
                    const SizedBox(width: 8),
                    vehicleStatusPill(vehicle.status, vehicle.isInspectionValid),
                  ],
                ),
                const SizedBox(height: 3),
                Text(parts.join(' · '), style: TextStyle(fontSize: 14, color: AppColors.text)),
                if (inspectionText != null) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    inspectionText,
                    style: TextStyle(
                      fontSize: 13,
                      color: vehicle.isInspectionValid ? AppColors.textMuted : AppColors.errorText,
                      fontWeight: vehicle.isInspectionValid ? FontWeight.w400 : FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
