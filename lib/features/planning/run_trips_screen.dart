// K5, K8: chuyến chạy của đơn, tạo từ kế hoạch, chốt lịch (theo màn N3-ChuyenChay trên canvas)
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push
import 'package:go_router/go_router.dart';

import '../../core/api/call.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/labels.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../auth/session_provider.dart';
import '../dispatch/dispatch_api.dart';
import '../orders/orders_api.dart' show orderDetailProvider;
import 'run_trips_api.dart';
import 'run_trips_providers.dart';
import '../../core/widgets/ios.dart';

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
        parts.add(t('planning.run.created', <String, Object?>{'count': result.createdCount}));
      } else {
        parts.add(t('planning.run.noneCreated'));
      }
      if (result.skippedCount > 0) {
        parts.add(t('planning.run.skipped', <String, Object?>{'count': result.skippedCount}));
      }
      for (final String reason in result.notAssigned) {
        parts.add(t('planning.run.manual', <String, Object?>{'reason': reason}));
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
          title: Text(t('planning.run.scheduleTitle')),
          content: Text(t('planning.run.scheduleBody')),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: Text(t('planning.run.cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(t('orderAction.schedule')),
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
              title: Text(t('planning.run.oversizeTitle')),
              content: Text(error.message),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(false);
                  },
                  child: Text(t('planning.run.dontSchedule')),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
                  onPressed: () {
                    Navigator.of(dialogContext).pop(true);
                  },
                  child: Text(t('planning.run.acknowledge')),
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
        showIosToast(context, t('planning.run.scheduled'));
      }
    } catch (error) {
      if (mounted) {
        showErrorSnackBar(context, error);
      }
    }
    ref.invalidate(runTripsProvider(widget.orderId));
    ref.invalidate(orderDetailProvider(widget.orderId));
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
    // Server quyết bước này còn chốt được không: đơn đã chốt lịch thì ẩn nút, không để bấm rồi báo lỗi
    final bool canSchedule = ref.watch(orderDetailProvider(widget.orderId)).value?.allowedActions.contains('schedule') ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('planning.run.title'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
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
                            style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.okText),
                          ),
                        ),
                      if (trips.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Center(
                            child: Text(
                              t('planning.run.empty'),
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
                canSchedule: canSchedule,
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
      return t('planning.run.noVehicle');
    }
    final List<String> plates = <String>[];
    for (final RunVehicle vehicle in trip.vehicles) {
      plates.add('${label(vehicleBaseTypeLabels, vehicle.baseType)} ${vehicle.plateNumber}');
    }
    String text = plates.join(' + ');
    for (final RunCrew member in trip.crew) {
      if (member.role == 'MainDriver') {
        text = '$text · ${t('planning.run.mainDriver', <String, Object?>{'name': member.fullName})}';
        break;
      }
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    // Nhãn: đỏ phải xử lý, vàng cần xem, xanh sẵn sàng
    String chipText = t('home.ready');
    bool mustFix = false;
    Color chipBackground = AppColors.okBackground;
    Color chipForeground = AppColors.okText;
    if (trip.hasError || trip.vehicles.isEmpty) {
      chipText = t('planning.run.mustFix');
      mustFix = true;
      chipBackground = AppColors.errorBackground;
      chipForeground = AppColors.errorText;
    } else if (trip.hasWarning || !trip.hasMainDriver) {
      chipText = t('planning.run.review');
      chipBackground = AppColors.warnBackground;
      chipForeground = AppColors.warnText;
    }

    final String day = formatVietnamDay(trip.startAt);
    final String start = formatVietnamClock(trip.startAt);
    final String end = formatVietnamClock(trip.endAt);
    String timeText = t('planning.tripNumber', <String, Object?>{'sequence': trip.plannedTripSequence});
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
          t('planning.run.estimatedFuel', <String, Object?>{'amount': formatMoney(trip.estimatedFuelCost)}),
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
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
                text: t('planning.assignTitle'),
                onTap: () {
                  context.push('/orders/$orderId/dispatch-trips/${trip.publicId}/assign');
                },
              ),
            ),
          if (canDispatch) const SizedBox(width: 8),
          Expanded(
            child: _SmallButton(
              text: t('planning.run.track'),
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
        color: AppColors.surface,
        border: Border.all(color: mustFix ? AppColors.errorBorder : AppColors.border),
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
        side: BorderSide(color: AppColors.inputBorder),
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
  final bool canSchedule;
  final bool busy;
  final VoidCallback onCreate;
  final VoidCallback onSchedule;

  const _BottomBar({
    required this.trips,
    required this.canDispatch,
    required this.canSchedule,
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
      decoration: BoxDecoration(
        color: AppColors.surface,
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
                side: BorderSide(color: AppColors.inputBorder),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              child: Text(t('planning.run.createFromPlan')),
            ),
            if (canSchedule) ...[
              const SizedBox(height: 8),
              FilledButton(
                onPressed: (busy || !allReady) ? null : onSchedule,
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CupertinoActivityIndicator(color: Colors.white),
                      )
                    : Text(t('orderAction.schedule')),
              ),
              const SizedBox(height: 6),
              Text(
                t('planning.run.scheduleHint'),
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
