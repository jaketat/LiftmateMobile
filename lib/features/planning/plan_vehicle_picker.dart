// Bảng chọn xe để đổi xe cho một chuyến trong kế hoạch (K2). Dùng danh sách xe của người 4 (fleet).
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api/paged_result.dart';
import '../../core/labels.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../fleet/fleet_api.dart';

// Mở bảng chọn. tractors = true: chọn đầu kéo; false: chọn xe chở (xe tải, moóc...). Trả về xe được chọn, bấm ra ngoài trả null
Future<Vehicle?> pickVehicle(BuildContext context, {required bool tractors}) {
  return showModalBottomSheet<Vehicle>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext sheetContext) {
      return _VehiclePickerSheet(tractors: tractors);
    },
  );
}

class _VehiclePickerSheet extends StatefulWidget {
  final bool tractors;

  const _VehiclePickerSheet({required this.tractors});

  @override
  State<_VehiclePickerSheet> createState() => _VehiclePickerSheetState();
}

class _VehiclePickerSheetState extends State<_VehiclePickerSheet> {
  late Future<List<Vehicle>> _vehiclesFuture;

  @override
  void initState() {
    super.initState();
    _vehiclesFuture = _load();
  }

  // Lấy trang đầu danh sách xe sẵn sàng, lọc theo đầu kéo hay xe chở
  Future<List<Vehicle>> _load() async {
    String? baseType;
    if (widget.tractors) {
      baseType = 'TractorHead';
    }
    final PagedResult<Vehicle> page = await fetchVehicles(1, '', baseType, 'Available');
    final List<Vehicle> vehicles = <Vehicle>[];
    for (final Vehicle vehicle in page.items) {
      final bool isTractor = vehicle.baseType == 'TractorHead';
      if (isTractor == widget.tractors) {
        vehicles.add(vehicle);
      }
    }
    return vehicles;
  }

  @override
  Widget build(BuildContext context) {
    String title = 'Chọn xe thay thế';
    if (widget.tractors) {
      title = 'Chọn đầu kéo cho moóc';
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            Flexible(
              child: FutureBuilder<List<Vehicle>>(
                future: _vehiclesFuture,
                builder: (BuildContext context, AsyncSnapshot<List<Vehicle>> snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CupertinoActivityIndicator(radius: 14)),
                    );
                  }
                  if (snapshot.hasError) {
                    return ErrorView(
                      message: errorMessage(snapshot.error!),
                      onRetry: () {
                        setState(() {
                          _vehiclesFuture = _load();
                        });
                      },
                    );
                  }
                  final List<Vehicle> vehicles = snapshot.data ?? <Vehicle>[];
                  if (vehicles.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: EmptyView(text: 'Không có xe sẵn sàng.'),
                    );
                  }
                  return ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      for (final Vehicle vehicle in vehicles) _VehicleTile(vehicle: vehicle),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VehicleTile extends StatelessWidget {
  final Vehicle vehicle;

  const _VehicleTile({required this.vehicle});

  @override
  Widget build(BuildContext context) {
    // Hết đăng kiểm thì mờ, không chọn được (server cũng chặn VEHICLE_NOT_ELIGIBLE)
    final bool usable = vehicle.isInspectionValid;

    return Opacity(
      opacity: usable ? 1 : 0.55,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: usable
              ? () {
                  Navigator.of(context).pop(vehicle);
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(vehicle.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                Text(
                  '${label(vehicleBaseTypeLabels, vehicle.baseType)} · ${vehicle.vehicleType} · tải ${vehicle.maxPayloadKg} kg',
                  style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
                if (!usable)
                  const Text('Hết đăng kiểm', style: TextStyle(fontSize: 12, color: AppColors.errorText)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
