// K9: điều phối hôm nay (theo màn N3-DieuPhoiHomNay trên canvas)
import 'dart:async';

import 'package:flutter/material.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/page_transition.dart';
import 'dispatch_api.dart';
import 'dispatch_providers.dart';

// weekday: 1 là thứ Hai ... 7 là Chủ nhật
String _weekdayName(int weekday) {
  return t('dispatch.weekday.$weekday');
}

class DispatchTodayScreen extends ConsumerStatefulWidget {
  const DispatchTodayScreen({super.key});

  @override
  ConsumerState<DispatchTodayScreen> createState() => _DispatchTodayScreenState();
}

class _DispatchTodayScreenState extends ConsumerState<DispatchTodayScreen> {
  // Đồng hồ tự tải lại mỗi 60 giây (doc mục 3.12)
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (Timer timer) {
      _reload();
    });
  }

  @override
  void dispose() {
    // Rời màn phải hủy đồng hồ, không thì app gọi API mãi (doc mục 3.15)
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _reload() {
    ref.invalidate(dispatchIssuesProvider);
    ref.invalidate(liveTripsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<DispatchIssue>> issuesValue = ref.watch(dispatchIssuesProvider);
    final AsyncValue<List<LiveTrip>> tripsValue = ref.watch(liveTripsProvider);

    final DateTime now = DateTime.now();
    final String subtitle = t('dispatch.today.subtitle', <String, Object?>{
      'weekday': _weekdayName(now.weekday),
      'date': dateFormat.format(now),
    });

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('dispatch.today.title'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
        ),
      ),
      // Kéo xuống để tải lại ngay
      body: RefreshIndicator(
        onRefresh: () async {
          _reload();
          await Future.wait<Object?>(<Future<Object?>>[
            ref.read(dispatchIssuesProvider.future).then<Object?>((Object? value) => value, onError: (Object e) => null),
            ref.read(liveTripsProvider.future).then<Object?>((Object? value) => value, onError: (Object e) => null),
          ]);
        },
        child: ListView(
          // Luôn kéo được, kể cả khi nội dung ngắn (để RefreshIndicator hoạt động)
          physics: const AlwaysScrollableScrollPhysics(),
          padding: withTabBarInset(context, const EdgeInsets.all(16)),
          children: [
            _SectionTitle(title: t('dispatch.today.issues'), count: issuesValue.value?.length),
            const SizedBox(height: 8),
            AsyncView<List<DispatchIssue>>(
              value: issuesValue,
              onRetry: () {
                ref.invalidate(dispatchIssuesProvider);
              },
              isEmpty: (List<DispatchIssue> issues) {
                return issues.isEmpty;
              },
              emptyText: t('dispatch.today.issuesEmpty'),
              builder: (List<DispatchIssue> issues) {
                return Column(
                  children: [
                    for (final DispatchIssue issue in issues) _IssueCard(issue: issue),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            _SectionTitle(title: t('dispatch.today.trips'), count: tripsValue.value?.length),
            const SizedBox(height: 8),
            AsyncView<List<LiveTrip>>(
              value: tripsValue,
              onRetry: () {
                ref.invalidate(liveTripsProvider);
              },
              isEmpty: (List<LiveTrip> trips) {
                return trips.isEmpty;
              },
              emptyText: t('dispatch.today.tripsEmpty'),
              builder: (List<LiveTrip> trips) {
                return Column(
                  children: [
                    for (final LiveTrip trip in trips) _TripCard(trip: trip),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              t('dispatch.today.legend'),
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

// Tiêu đề nhóm: chữ hoa nhỏ bên trái, số lượng bên phải
class _SectionTitle extends StatelessWidget {
  final String title;
  // null: chưa có dữ liệu thì không hiện số
  final int? count;

  const _SectionTitle({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    final TextStyle style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      color: AppColors.textMuted,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title.toUpperCase(), style: style),
          if (count != null) Text('$count', style: style),
        ],
      ),
    );
  }
}

// Khung trắng bo góc, bấm được, dùng chung cho việc cần xử lý và chuyến
Widget _tappableCard({required VoidCallback? onTap, required Widget child}) {
  return Card(
    margin: const EdgeInsets.only(bottom: 8),
    color: AppColors.surface,
    elevation: 0,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: AppColors.border),
      borderRadius: BorderRadius.circular(12),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: child,
      ),
    ),
  );
}

// Một việc cần xử lý: viền trái đỏ (Error) hoặc vàng (Warning)
class _IssueCard extends StatelessWidget {
  final DispatchIssue issue;

  const _IssueCard({required this.issue});

  @override
  Widget build(BuildContext context) {
    Color barColor = const Color(0xFFD29B00);
    Color titleColor = AppColors.warnText;
    if (issue.isError) {
      barColor = AppColors.errorText;
      titleColor = AppColors.errorText;
    }

    // Có chuyến thì mở theo dõi chuyến; chưa có chuyến thì mở danh sách chuyến chạy của đơn
    VoidCallback? onTap;
    final String? orderId = issue.orderId;
    if (orderId != null) {
      onTap = () {
        if (issue.tripId != null) {
          context.push('/orders/$orderId/trips/${issue.tripId}/track');
        } else {
          context.push('/orders/$orderId/dispatch-trips');
        }
      };
    }

    final List<String> detailParts = <String>[];
    if (issue.orderCode.isNotEmpty) {
      detailParts.add(issue.orderCode);
    }
    if (issue.date != null) {
      detailParts.add(t('dispatch.today.issueDate', <String, Object?>{'date': formatDate(issue.date)}));
    }

    return _tappableCard(
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(color: barColor, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    issue.message,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: titleColor),
                  ),
                  if (detailParts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(detailParts.join(' · '), style: const TextStyle(fontSize: 13)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Một chuyến trong ngày: chấm tín hiệu + biển số, mã đơn + dòng trạng thái
class _TripCard extends StatelessWidget {
  final LiveTrip trip;

  const _TripCard({required this.trip});

  // Màu chấm theo tín hiệu
  Color _dotColor() {
    switch (trip.signal) {
      case 'Live':
        return const Color(0xFF12B76A);
      case 'Slow':
        return const Color(0xFFD29B00);
      case 'Lost':
        return AppColors.errorText;
      default:
        return const Color(0xFF98A2B3);
    }
  }

  // Dòng phụ, ví dụ "Mất tín hiệu · lần cuối 09:41"
  String _statusLine() {
    final List<String> parts = <String>[signalLabel(trip.signal)];
    switch (trip.signal) {
      case 'NotStarted':
        final String start = formatVietnamClock(trip.startAt);
        if (start.isNotEmpty) {
          parts.add(start);
        }
        break;
      case 'Lost':
        final String last = formatVietnamClock(trip.lastUpdateAt);
        if (last.isNotEmpty) {
          parts.add(t('dispatch.today.lastSeen', <String, Object?>{'time': last}));
        }
        break;
      case 'Live':
      case 'Slow':
        final String eta = formatVietnamClock(trip.etaArriveAt);
        if (eta.isNotEmpty) {
          String etaKey = 'dispatch.today.eta';
          if (trip.etaApproximate) {
            etaKey = 'dispatch.today.etaApprox';
          }
          parts.add(t(etaKey, <String, Object?>{'time': eta}));
        }
        break;
    }
    if (trip.isLate) {
      parts.add(t('dispatch.late', <String, Object?>{'minutes': trip.delayMinutes}));
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    String plates = trip.plateNumbers.join(' + ');
    if (plates.isEmpty) {
      plates = t('dispatch.noVehicle');
    }

    return _tappableCard(
      onTap: () {
        context.push('/orders/${trip.orderId}/trips/${trip.tripId}/track');
      },
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: _dotColor(), shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$plates · ${trip.orderCode}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                Text(_statusLine(), style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
          ),
          // Nhãn báo hỏng: phải dừng xe thì đỏ, còn lại vàng
          if (trip.hasOpenBreakdown || trip.hasMustStopBreakdown) _BreakdownChip(mustStop: trip.hasMustStopBreakdown),
        ],
      ),
    );
  }
}

class _BreakdownChip extends StatelessWidget {
  final bool mustStop;

  const _BreakdownChip({required this.mustStop});

  @override
  Widget build(BuildContext context) {
    Color background = AppColors.warnBackground;
    Color foreground = AppColors.warnText;
    String text = t('dispatch.today.breakdown');
    if (mustStop) {
      background = AppColors.errorBackground;
      foreground = AppColors.errorText;
      text = t('dispatch.today.mustStop');
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: foreground)),
    );
  }
}
