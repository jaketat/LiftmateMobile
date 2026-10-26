// K6, K7: gợi ý xe và tài xế, gán, xếp lại khi bị chặn (theo màn N3-GoiYXe và N3-XepKhongVua trên canvas)
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.pop
import 'package:go_router/go_router.dart';

import '../../core/api/call.dart';
import '../../core/format.dart';
import '../../core/labels.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../dispatch/dispatch_api.dart';
import 'run_trips_api.dart';
import 'run_trips_providers.dart';

class AssignScreen extends ConsumerStatefulWidget {
  final String orderId;
  final String tripId;

  const AssignScreen({super.key, required this.orderId, required this.tripId});

  @override
  ConsumerState<AssignScreen> createState() => _AssignScreenState();
}

class _AssignScreenState extends ConsumerState<AssignScreen> {
  // Xe đang chọn
  final Set<String> _vehicleIds = <String>{};
  // Lái chính của từng xe: vehicleId -> userId
  final Map<String, String> _driverByVehicle = <String, String>{};
  // Phụ xe đang chọn
  final Set<String> _assistantIds = <String>{};
  // Đã điền sẵn từ phân công hiện tại chưa (chỉ làm một lần)
  bool _initialized = false;
  // true: đang lưu hoặc đang xếp lại, khóa nút
  bool _busy = false;

  // Lần đầu có dữ liệu: chọn sẵn xe và tổ lái hiện tại; chuyến chưa có xe thì chọn xe đúng kế hoạch đầu tiên
  void _initFrom(Candidates candidates) {
    if (_initialized) {
      return;
    }
    _initialized = true;
    for (final RunVehicle vehicle in candidates.trip.vehicles) {
      _vehicleIds.add(vehicle.publicId);
    }
    for (final RunCrew member in candidates.trip.crew) {
      if (member.role == 'MainDriver' && member.vehicleId != null) {
        _driverByVehicle[member.vehicleId!] = member.userId;
      } else if (member.role == 'Assistant') {
        _assistantIds.add(member.userId);
      }
    }
    if (_vehicleIds.isEmpty) {
      for (final VehicleCandidate candidate in candidates.vehicles) {
        if (candidate.isEligible && candidate.matchesPlan) {
          _vehicleIds.add(candidate.vehicle.publicId);
          break;
        }
      }
    }
  }

  // Các xe đang chọn, theo thứ tự trong danh sách gợi ý
  List<VehicleCandidate> _selectedVehicles(Candidates candidates) {
    final List<VehicleCandidate> selected = <VehicleCandidate>[];
    for (final VehicleCandidate candidate in candidates.vehicles) {
      if (_vehicleIds.contains(candidate.vehicle.publicId)) {
        selected.add(candidate);
      }
    }
    return selected;
  }

  List<CrewAssignment> _buildCrew(Candidates candidates) {
    final List<CrewAssignment> crew = <CrewAssignment>[];
    for (final VehicleCandidate candidate in _selectedVehicles(candidates)) {
      final String? driverId = _driverByVehicle[candidate.vehicle.publicId];
      if (candidate.vehicle.needsDriver && driverId != null) {
        crew.add((userId: driverId, role: 'MainDriver', vehicleId: candidate.vehicle.publicId));
      }
    }
    for (final String userId in _assistantIds) {
      crew.add((userId: userId, role: 'Assistant', vehicleId: null));
    }
    return crew;
  }

  Future<void> _assign(Candidates candidates) async {
    final List<VehicleCandidate> selected = _selectedVehicles(candidates);
    if (selected.isEmpty) {
      showErrorSnackBar(context, ApiException(null, null, 'Chọn ít nhất một xe.'));
      return;
    }
    for (final VehicleCandidate candidate in selected) {
      if (candidate.vehicle.needsDriver && _driverByVehicle[candidate.vehicle.publicId] == null) {
        showErrorSnackBar(
          context,
          ApiException(null, null, 'Chọn lái chính cho xe ${candidate.vehicle.plateNumber}.'),
        );
        return;
      }
    }

    setState(() {
      _busy = true;
    });
    try {
      await _sendAssignment(candidates);
      _finish('Đã lưu phân công.');
      return;
    } on ApiException catch (error) {
      if (error.code == 'VEHICLE_LAYOUT_UNSAFE' && mounted) {
        await _handleUnsafe(candidates, error);
      } else {
        _reportError(error);
      }
    } catch (error) {
      _reportError(error);
    }
    if (mounted) {
      setState(() {
        _busy = false;
      });
    }
  }

  Future<void> _sendAssignment(Candidates candidates) {
    final List<String> vehicleIds = <String>[];
    for (final VehicleCandidate candidate in _selectedVehicles(candidates)) {
      vehicleIds.add(candidate.vehicle.publicId);
    }
    return assignRunTrip(
      widget.orderId,
      widget.tripId,
      vehicleIds: vehicleIds,
      crew: _buildCrew(candidates),
      revision: candidates.trip.revision,
    );
  }

  // K7: hàng không xếp vừa xe. Hỏi xếp lại cho chính xe này hay chọn xe khác
  Future<void> _handleUnsafe(Candidates candidates, ApiException error) async {
    final bool? replan = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          icon: const CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.errorBackground,
            child: Icon(Icons.warning_amber_rounded, size: 28, color: AppColors.errorText),
          ),
          title: const Text('Hàng không xếp vừa xe này', textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(error.message, style: const TextStyle(fontSize: 15, height: 1.5)),
              const SizedBox(height: 12),
              const Text(
                'Cho máy xếp lại hàng của chuyến trên chính xe này. Không vừa thì chọn xe lớn hơn.',
                style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.textMuted),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actionsOverflowDirection: VerticalDirection.down,
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Xếp lại cho xe này'),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Chọn xe khác'),
            ),
          ],
        );
      },
    );
    if (replan != true || !mounted) {
      return;
    }

    // Xe chở là xe không phải đầu kéo; moóc thì kèm đầu kéo
    String? carrierId;
    String? tractorId;
    for (final VehicleCandidate candidate in _selectedVehicles(candidates)) {
      if (candidate.vehicle.baseType == 'TractorHead') {
        tractorId = candidate.vehicle.publicId;
      } else {
        carrierId ??= candidate.vehicle.publicId;
      }
    }
    if (carrierId == null && tractorId != null) {
      carrierId = tractorId;
      tractorId = null;
    }
    if (carrierId == null) {
      return;
    }

    try {
      await replanForVehicle(widget.orderId, widget.tripId, carrierId, tractorId);
      // Xếp lại đạt: gán lại xe
      await _sendAssignment(candidates);
      _finish('Đã xếp lại và gán xe.');
    } catch (error) {
      // Xếp lại không đạt: server trả câu giải thích, gợi ý chọn xe lớn hơn
      _reportError(error);
    }
  }

  void _reportError(Object error) {
    if (!mounted) {
      return;
    }
    showErrorSnackBar(context, error);
    // Người khác vừa sửa chuyến: tải lại để lấy revision mới
    if (error is ApiException && error.code != null && error.code!.endsWith('_CHANGED_CONCURRENTLY')) {
      ref.invalidate(candidatesProvider(widget.tripId));
    }
  }

  // Xong: tải lại danh sách chuyến chạy rồi quay về
  void _finish(String message) {
    ref.invalidate(runTripsProvider(widget.orderId));
    ref.invalidate(candidatesProvider(widget.tripId));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Candidates> candidatesValue = ref.watch(candidatesProvider(widget.tripId));

    // Dòng phụ: "Chuyến 3 · 21/10 · 07:30 – 12:00"
    String subtitle = '';
    final Candidates? loaded = candidatesValue.value;
    if (loaded != null) {
      final RunTrip trip = loaded.trip;
      subtitle = 'Chuyến ${trip.plannedTripSequence}';
      final String day = formatVietnamDay(trip.startAt);
      if (day.isNotEmpty) {
        subtitle = '$subtitle · $day · ${formatVietnamClock(trip.startAt)} – ${formatVietnamClock(trip.endAt)}';
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Gán xe, tài xế', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            if (subtitle.isNotEmpty)
              Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
        ),
      ),
      body: AsyncView<Candidates>(
        value: candidatesValue,
        onRetry: () {
          ref.invalidate(candidatesProvider(widget.tripId));
        },
        builder: (Candidates candidates) {
          _initFrom(candidates);
          return _buildForm(candidates);
        },
      ),
    );
  }

  Widget _buildForm(Candidates candidates) {
    final List<Widget> children = <Widget>[
      const _SectionTitle('Xe gợi ý'),
    ];

    if (candidates.vehicles.isEmpty) {
      children.add(const Text('Không có xe nào để gợi ý.', style: TextStyle(color: AppColors.textMuted)));
    }
    for (final VehicleCandidate candidate in candidates.vehicles) {
      final String id = candidate.vehicle.publicId;
      children.add(
        _OptionTile(
          selected: _vehicleIds.contains(id),
          enabled: candidate.isEligible,
          multi: true,
          onTap: () {
            setState(() {
              if (_vehicleIds.contains(id)) {
                _vehicleIds.remove(id);
                _driverByVehicle.remove(id);
              } else {
                _vehicleIds.add(id);
              }
            });
          },
          title: candidate.vehicle.plateNumber,
          chip: candidate.matchesPlan ? 'Đúng kế hoạch' : null,
          subtitle:
              '${label(vehicleBaseTypeLabels, candidate.vehicle.baseType)} · ${candidate.vehicle.vehicleType} · tải ${formatKg(candidate.vehicle.maxPayloadKg)}',
          issues: candidate.issues,
        ),
      );
    }

    // Lái chính cho từng xe tự chạy đang chọn
    final List<StaffCandidate> drivers = <StaffCandidate>[];
    for (final StaffCandidate person in candidates.staff) {
      if (person.isDriver) {
        drivers.add(person);
      }
    }
    for (final VehicleCandidate candidate in _selectedVehicles(candidates)) {
      if (!candidate.vehicle.needsDriver) {
        continue;
      }
      final String vehicleId = candidate.vehicle.publicId;
      children.add(const SizedBox(height: 8));
      children.add(_SectionTitle('Lái chính cho ${candidate.vehicle.plateNumber}'));
      if (drivers.isEmpty) {
        children.add(const Text('Không có ai làm lái chính được.', style: TextStyle(color: AppColors.textMuted)));
      }
      for (final StaffCandidate person in drivers) {
        children.add(
          _OptionTile(
            selected: _driverByVehicle[vehicleId] == person.userId,
            enabled: person.isEligible,
            multi: false,
            onTap: () {
              setState(() {
                _driverByVehicle[vehicleId] = person.userId;
                // Một người đã làm lái chính thì không đồng thời làm phụ xe
                _assistantIds.remove(person.userId);
              });
            },
            title: person.fullName,
            chip: null,
            subtitle: person.phone,
            issues: person.issues,
          ),
        );
      }
    }

    // Phụ xe: không bắt buộc, chọn nhiều
    final Set<String> mainDriverIds = _driverByVehicle.values.toSet();
    final List<StaffCandidate> assistants = <StaffCandidate>[];
    for (final StaffCandidate person in candidates.staff) {
      if (!mainDriverIds.contains(person.userId)) {
        assistants.add(person);
      }
    }
    if (assistants.isNotEmpty) {
      children.add(const SizedBox(height: 8));
      children.add(const _SectionTitle('Phụ xe (không bắt buộc)'));
      for (final StaffCandidate person in assistants) {
        children.add(
          _OptionTile(
            selected: _assistantIds.contains(person.userId),
            enabled: person.isEligible,
            multi: true,
            onTap: () {
              setState(() {
                if (_assistantIds.contains(person.userId)) {
                  _assistantIds.remove(person.userId);
                } else {
                  _assistantIds.add(person.userId);
                }
              });
            },
            title: person.fullName,
            chip: null,
            subtitle: person.phone,
            issues: person.issues,
          ),
        );
      }
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: children,
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(
            top: false,
            child: FilledButton(
              onPressed: _busy
                  ? null
                  : () {
                      _assign(candidates);
                    },
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CupertinoActivityIndicator(color: Colors.white),
                    )
                  : const Text('Lưu phân công'),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

// Một dòng chọn (xe, lái chính, phụ xe): ô tròn hoặc vuông, tên, nhãn, mô tả, lý do
class _OptionTile extends StatelessWidget {
  final bool selected;
  // false: không chọn được, hiện mờ (xe, người không hợp lệ vẫn hiện kèm lý do)
  final bool enabled;
  // true: ô vuông (chọn nhiều); false: ô tròn (chọn một)
  final bool multi;
  final VoidCallback onTap;
  final String title;
  final String? chip;
  final String subtitle;
  final List<RunIssue> issues;

  const _OptionTile({
    required this.selected,
    required this.enabled,
    required this.multi,
    required this.onTap,
    required this.title,
    required this.chip,
    required this.subtitle,
    required this.issues,
  });

  @override
  Widget build(BuildContext context) {
    IconData icon;
    if (multi) {
      icon = selected ? Icons.check_box : Icons.check_box_outline_blank;
    } else {
      icon = selected ? Icons.radio_button_checked : Icons.radio_button_unchecked;
    }

    final List<Widget> lines = <Widget>[
      Row(
        children: [
          Flexible(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
          if (chip != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppColors.okBackground, borderRadius: BorderRadius.circular(999)),
              child: Text(
                chip!,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.okText),
              ),
            ),
          ],
        ],
      ),
    ];
    if (subtitle.isNotEmpty && enabled) {
      lines.add(Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)));
    }
    for (final RunIssue issue in issues) {
      lines.add(
        Text(
          issue.message,
          style: TextStyle(fontSize: 12, color: issue.isError ? AppColors.errorText : AppColors.warnText),
        ),
      );
    }

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: selected ? AppColors.navy : AppColors.border, width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(icon, color: selected ? AppColors.navy : AppColors.inputBorder, size: 24),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
