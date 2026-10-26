// K5, K8: chuyến chạy của đơn, tạo từ kế hoạch, chốt lịch (theo màn N3-ChuyenChay trên canvas)
import 'package:flutter/material.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push
import 'package:go_router/go_router.dart';

import '../../core/api/call.dart';
import '../../core/format.dart';
import '../../core/labels.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../auth/session_provider.dart';
import '../dispatch/dispatch_api.dart';
import 'run_trips_api.dart';
import 'run_trips_providers.dart';

class RunTripsScreen extends ConsumerStatefulWidget {
  final String orderId;

  const RunTripsScreen({super.key, required this.orderId});

  @override
  ConsumerState<RunTripsScreen> createState() => _RunTripsScreenState();
}

class _RunTripsScreenState extends ConsumerState<RunTripsScreen> {
  // true: đang tạo chuyến hoặc đang chốt lịch, khóa nút
  bool _busy = false;
  // Câu báo xanh sau khi tạo chuyến chạy từ kế hoạch; rỗng thì không hiện
  String _createdMessage = '';

  Future<void> _createFromPlan() async {
    setState(() {
      _busy = true;
    });
    try {
      final CreateRunTripsResult result = await createRunTripsFromPlan(widget.orderId);
      final List<String> parts = <String>[];
      if (result.createdCount > 0) {
        parts.add('Đã tạo ${result.createdCount} chuyến từ kế hoạch, gán sẵn xe.');
      } else {
        parts.add('Không có chuyến mới để tạo.');
      }
      if (result.skippedCount > 0) {
        parts.add('${result.skippedCount} chuyến đã có từ trước.');
      }
      for (final String reason in result.notAssigned) {
        parts.add('$reason (gán tay).');
      }
      _createdMessage = parts.join(' ');
    } catch (error) {
      if (mounted) {
        showErrorSnackBar(context, error);
      }
    }
    ref.invalidate(runTripsProvider(widget.orderId));
    if (mounted) {
      setState(() {
        _busy = false;
      });
    }
  }

  // Chốt lịch: hỏi xác nhận; đơn quá khổ thì hỏi thêm một hộp cảnh báo rồi gửi lại với acknowledgeOversize
  Future<void> _schedule() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Chốt lịch?'),
          content: const Text('Chốt xong, tài xế thấy chuyến trong app của mình.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Hủy'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Chốt lịch'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _busy = true;
    });
    try {
      try {
        await scheduleOrder(widget.orderId, acknowledgeOversize: false);
      } on ApiException catch (error) {
        if (error.code != 'OVERSIZE_ACKNOWLEDGEMENT_REQUIRED') {
          rethrow;
        }
        if (!mounted) {
          return;
        }
        // Hộp xác nhận cảnh báo quá khổ rồi gửi lại với true
        final bool? acknowledged = await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              title: const Text('Hàng quá khổ'),
              content: Text(error.message),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(false);
                  },
                  child: const Text('Không chốt'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
                  onPressed: () {
                    Navigator.of(dialogContext).pop(true);
                  },
                  child: const Text('Tôi đã đọc cảnh báo'),
                ),
              ],
            );
          },
        );
        if (acknowledged != true) {
          if (mounted) {
            setState(() {
              _busy = false;
            });
          }
          return;
        }
        await scheduleOrder(widget.orderId, acknowledgeOversize: true);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã chốt lịch.')));
      }
    } catch (error) {
      if (mounted) {
        showErrorSnackBar(context, error);
      }
    }
    ref.invalidate(runTripsProvider(widget.orderId));
    if (mounted) {
      setState(() {
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<RunTrip>> tripsValue = ref.watch(runTripsProvider(widget.orderId));
    final Session? session = ref.watch(sessionProvider).value;
    final bool canDispatch = session != null && session.can('Orders.Dispatch');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chuyến chạy', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: AsyncView<List<RunTrip>>(
        value: tripsValue,
        onRetry: () {
          ref.invalidate(runTripsProvider(widget.orderId));
        },
        builder: (List<RunTrip> trips) {
          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () {
                    return ref.refresh(runTripsProvider(widget.orderId).future);
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_createdMessage.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.okBackground,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _createdMessage,
                            style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.okText),
                          ),
                        ),
                      if (trips.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Center(
                            child: Text(
                              'Chưa có chuyến chạy nào. Duyệt kế hoạch rồi tạo chuyến chạy từ kế hoạch.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textMuted),
                            ),
                          ),
                        ),
                      for (final RunTrip trip in trips) ...[
                        const SizedBox(height: 10),
                        _RunTripCard(orderId: widget.orderId, trip: trip, canDispatch: canDispatch),
                      ],
                    ],
                  ),
                ),
              ),
              _BottomBar(
                trips: trips,
                canDispatch: canDispatch,
                busy: _busy,
                onCreate: _createFromPlan,
                onSchedule: _schedule,
              ),
            ],
          );
        },
      ),
    );
  }
}

// Một chuyến chạy: giờ, nhãn trạng thái, xe + lái chính, vấn đề, nút Theo dõi / Gán xe
class _RunTripCard extends StatelessWidget {
  final String orderId;
  final RunTrip trip;
  final bool canDispatch;

  const _RunTripCard({required this.orderId, required this.trip, required this.canDispatch});

  // Dòng xe: "Xe 51C-900.01 · Lái chính: Tài xế 1" hoặc "Chưa có xe"
  String _vehicleText() {
    if (trip.vehicles.isEmpty) {
      return 'Chưa có xe';
    }
    final List<String> plates = <String>[];
    for (final RunVehicle vehicle in trip.vehicles) {
      plates.add('${label(vehicleBaseTypeLabels, vehicle.baseType)} ${vehicle.plateNumber}');
    }
    String text = plates.join(' + ');
    for (final RunCrew member in trip.crew) {
      if (member.role == 'MainDriver') {
        text = '$text · Lái chính: ${member.fullName}';
        break;
      }
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    // Nhãn: đỏ phải xử lý, vàng cần xem, xanh sẵn sàng
    String chipText = 'Sẵn sàng';
    Color chipBackground = AppColors.okBackground;
    Color chipForeground = AppColors.okText;
    if (trip.hasError || trip.vehicles.isEmpty) {
      chipText = 'Phải xử lý';
      chipBackground = AppColors.errorBackground;
      chipForeground = AppColors.errorText;
    } else if (trip.hasWarning || !trip.hasMainDriver) {
      chipText = 'Cần xem';
      chipBackground = AppColors.warnBackground;
      chipForeground = AppColors.warnText;
    }

    final String day = formatVietnamDay(trip.startAt);
    final String start = formatVietnamClock(trip.startAt);
    final String end = formatVietnamClock(trip.endAt);
    String timeText = 'Chuyến ${trip.plannedTripSequence}';
    if (day.isNotEmpty) {
      timeText = '$timeText · $day · $start – $end';
    }

    final List<Widget> children = <Widget>[
      Row(
        children: [
          Expanded(child: Text(timeText, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: chipBackground, borderRadius: BorderRadius.circular(999)),
            child: Text(chipText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: chipForeground)),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(_vehicleText(), style: const TextStyle(fontSize: 14)),
    ];

    // Vấn đề: Error đỏ, Warning vàng. Chuyến có xe mà thiếu lái chính cũng nhắc
    for (final RunIssue issue in trip.issues) {
      children.add(const SizedBox(height: 6));
      children.add(_IssueBox(issue: issue));
    }
    if (trip.estimatedFuelCost != null) {
      children.add(const SizedBox(height: 6));
      children.add(
        Text(
          'Dầu ước tính ${formatMoney(trip.estimatedFuelCost)}',
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
      );
    }

    children.add(const SizedBox(height: 8));
    children.add(
      Row(
        children: [
          if (canDispatch)
            Expanded(
              child: _SmallButton(
                text: 'Gán xe, tài xế',
                onTap: () {
                  context.push('/orders/$orderId/dispatch-trips/${trip.publicId}/assign');
                },
              ),
            ),
          if (canDispatch) const SizedBox(width: 8),
          Expanded(
            child: _SmallButton(
              text: 'Theo dõi',
              onTap: () {
                context.push('/orders/$orderId/trips/${trip.publicId}/track');
              },
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: chipText == 'Phải xử lý' ? const Color(0xFFF3B8B2) : AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

class _IssueBox extends StatelessWidget {
  final RunIssue issue;

  const _IssueBox({required this.issue});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: issue.isError ? AppColors.errorBackground : AppColors.warnBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        issue.message,
        style: TextStyle(fontSize: 13, color: issue.isError ? AppColors.errorText : AppColors.warnText),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _SmallButton({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(40),
        foregroundColor: AppColors.navy,
        side: const BorderSide(color: AppColors.inputBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      child: Text(text),
    );
  }
}

// Dưới màn: "Tạo chuyến chạy từ kế hoạch" và "Chốt lịch" (chỉ mở khi mọi chuyến đủ xe và lái chính)
class _BottomBar extends StatelessWidget {
  final List<RunTrip> trips;
  final bool canDispatch;
  final bool busy;
  final VoidCallback onCreate;
  final VoidCallback onSchedule;

  const _BottomBar({
    required this.trips,
    required this.canDispatch,
    required this.busy,
    required this.onCreate,
    required this.onSchedule,
  });

  @override
  Widget build(BuildContext context) {
    // Không có quyền điều xe thì không có nút nào (doc mục 2.8)
    if (!canDispatch) {
      return const SizedBox.shrink();
    }

    bool allReady = trips.isNotEmpty;
    for (final RunTrip trip in trips) {
      if (!trip.isReady) {
        allReady = false;
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton(
              onPressed: busy ? null : onCreate,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: AppColors.navy,
                side: const BorderSide(color: AppColors.inputBorder),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              child: const Text('Tạo chuyến chạy từ kế hoạch'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: (busy || !allReady) ? null : onSchedule,
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Chốt lịch'),
            ),
            const SizedBox(height: 6),
            const Text(
              'Chốt lịch mở khi mọi chuyến đã có xe và lái chính, không còn lỗi đỏ.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
