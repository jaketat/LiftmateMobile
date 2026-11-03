// K10: theo dõi chuyến (theo màn N3-TheoDoiChuyen trên canvas)
import 'dart:async';

import 'package:flutter/material.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// url_launcher: mở Google Maps, bấm gọi điện
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n.dart';
import '../../core/labels.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import 'dispatch_api.dart';
import 'dispatch_providers.dart';
import '../../core/widgets/ios.dart';
import '../../core/widgets/page_transition.dart';

// Câu to ở đầu màn, theo tín hiệu
String _signalHeadline(String? signal) {
  final String key = 'dispatch.headline.$signal';
  return I18n.has(key) ? t(key) : (signal ?? '');
}

class TripTrackScreen extends ConsumerStatefulWidget {
  final TrackKey trackKey;

  const TripTrackScreen({super.key, required this.trackKey});

  @override
  ConsumerState<TripTrackScreen> createState() => _TripTrackScreenState();
}

class _TripTrackScreenState extends ConsumerState<TripTrackScreen> {
  // Tự tải lại mỗi 60 giây (doc mục 3.13)
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (Timer timer) {
      ref.invalidate(tripTrackProvider(widget.trackKey));
    });
  }

  @override
  void dispose() {
    // Rời màn phải hủy đồng hồ, không thì app gọi API mãi (doc mục 3.15)
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<TripTrack> trackValue = ref.watch(tripTrackProvider(widget.trackKey));

    // Dòng phụ ở thanh trên: "DH-202610-0013 · Lắp máy Đông Á" (chỉ có khi đã tải xong)
    String subtitle = '';
    final TripTrack? track = trackValue.value;
    if (track != null) {
      final List<String> parts = <String>[];
      if (track.trip.orderCode.isNotEmpty) {
        parts.add(track.trip.orderCode);
      }
      if (track.trip.customerName.isNotEmpty) {
        parts.add(track.trip.customerName);
      }
      subtitle = parts.join(' · ');
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('dispatch.track.title'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            if (subtitle.isNotEmpty)
              Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
        ),
      ),
      body: AsyncView<TripTrack>(
        value: trackValue,
        onRetry: () {
          ref.invalidate(tripTrackProvider(widget.trackKey));
        },
        builder: (TripTrack track) {
          return RefreshIndicator(
            onRefresh: () {
              return ref.refresh(tripTrackProvider(widget.trackKey).future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: withTabBarInset(context, const EdgeInsets.all(16)),
              children: [
                _StatusPanel(trip: track.trip),
                const SizedBox(height: 12),
                _VehicleCard(trip: track.trip),
                const SizedBox(height: 12),
                _StopsCard(stops: track.stops),
                const SizedBox(height: 12),
                Text(
                  t('dispatch.track.noPath'),
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// Số phút từ lúc đó tới giờ, vd "6 phút trước"; null nếu chưa có mốc
String? _agoText(String? isoText) {
  if (isoText == null || isoText.isEmpty) {
    return null;
  }
  final Duration passed = DateTime.now().toUtc().difference(DateTime.parse(isoText).toUtc());
  final int minutes = passed.inMinutes;
  if (minutes < 1) {
    return t('dispatch.track.justNow');
  }
  if (minutes < 60) {
    return t('dispatch.track.minutesAgo', <String, Object?>{'count': minutes});
  }
  return t('dispatch.track.hoursAgo', <String, Object?>{'count': passed.inHours});
}

// Khung màu đầu màn: tín hiệu, giờ dự kiến tới, trễ hay đúng giờ
class _StatusPanel extends StatelessWidget {
  final LiveTrip trip;

  const _StatusPanel({required this.trip});

  @override
  Widget build(BuildContext context) {
    Color background = AppColors.fillSoft;
    Color foreground = AppColors.textMuted;
    Color dot = const Color(0xFF98A2B3);
    switch (trip.signal) {
      case 'Live':
        background = AppColors.okBackground;
        foreground = AppColors.okText;
        dot = const Color(0xFF12B76A);
        break;
      case 'Slow':
        background = AppColors.warnBackground;
        foreground = AppColors.warnText;
        dot = const Color(0xFFD29B00);
        break;
      case 'Lost':
        background = AppColors.errorBackground;
        foreground = AppColors.errorText;
        dot = AppColors.errorText;
        break;
    }

    String headline = _signalHeadline(trip.signal);
    final String? ago = _agoText(trip.lastUpdateAt);
    if (ago != null) {
      headline = t('dispatch.track.updated', <String, Object?>{'status': headline, 'ago': ago});
    }

    // Giờ dự kiến tới
    String etaText = t('dispatch.track.etaNone');
    final String eta = formatVietnamClock(trip.etaArriveAt);
    if (eta.isNotEmpty) {
      etaText = eta;
      if (trip.etaApproximate) {
        etaText = t('dispatch.track.etaApprox', <String, Object?>{'time': eta});
      }
    }

    // So với giờ kết thúc
    String delayText = t('dispatch.track.onTime');
    Color delayColor = AppColors.text;
    if (trip.isLate) {
      delayText = t('dispatch.late', <String, Object?>{'minutes': trip.delayMinutes});
      delayColor = AppColors.errorText;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  headline,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: foreground),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _Kpi(title: t('dispatch.track.kpiEta'), value: etaText, valueColor: AppColors.text)),
              Expanded(child: _Kpi(title: t('dispatch.track.kpiDelay'), value: delayText, valueColor: delayColor)),
            ],
          ),
          if (trip.hasOpenBreakdown || trip.hasMustStopBreakdown)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                trip.hasMustStopBreakdown ? t('dispatch.track.breakdownMustStop') : t('dispatch.track.breakdownOpen'),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.errorText),
              ),
            ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  final String title;
  final String value;
  final Color valueColor;

  const _Kpi({required this.title, required this.value, required this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: valueColor)),
      ],
    );
  }
}

// Khung trắng bo góc dùng chung
BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: AppColors.surface,
    border: Border.all(color: AppColors.border),
    borderRadius: BorderRadius.circular(14),
  );
}

// Mở một đường dẫn ngoài app (Google Maps, trình gọi điện). Không mở được thì báo bằng thanh dưới màn
Future<void> _openExternal(BuildContext context, Uri uri) async {
  bool opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (!opened && context.mounted) {
    showIosToast(context, t('dispatch.track.openFailed'), isError: true);
  }
}

// Xe, lái chính, nút "Gọi tài xế" và "Xem trên bản đồ"
class _VehicleCard extends StatelessWidget {
  final LiveTrip trip;

  const _VehicleCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    String vehicleText = t('dispatch.noVehicle');
    if (trip.vehicleLines.isNotEmpty) {
      vehicleText = trip.vehicleLines.join('\n');
    }

    final TripCrewMember? driver = trip.mainDriver;
    String driverText = t('dispatch.track.noDriver');
    if (driver != null) {
      driverText = driver.fullName;
      if (driver.phone.isNotEmpty) {
        driverText = '${driver.fullName} · ${driver.phone}';
      }
    }

    // Nút bản đồ chỉ hiện khi tài xế chia sẻ vị trí và vị trí đủ chính xác (doc mục 3.13)
    final TripLocation? location = trip.lastLocation;
    final bool canShowMap = trip.sharingLocation && location != null && location.usable;
    final bool canCall = driver != null && driver.phone.isNotEmpty;

    final List<Widget> buttons = <Widget>[];
    if (canCall) {
      buttons.add(
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.phone_outlined, size: 18),
            label: Text(t('dispatch.track.callDriver')),
            style: _outlinedStyle(),
            onPressed: () {
              _openExternal(context, Uri(scheme: 'tel', path: driver.phone));
            },
          ),
        ),
      );
    }
    if (canShowMap) {
      if (buttons.isNotEmpty) {
        buttons.add(const SizedBox(width: 8));
      }
      buttons.add(
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.place_outlined, size: 18),
            label: Text(t('dispatch.track.viewMap')),
            style: _outlinedStyle(),
            onPressed: () {
              _openExternal(
                context,
                Uri.parse('https://www.google.com/maps/search/?api=1&query=${location.latitude},${location.longitude}'),
              );
            },
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow(title: t('dispatch.track.vehicle'), value: vehicleText),
          const SizedBox(height: 8),
          _InfoRow(title: t('dispatch.track.mainDriver'), value: driverText),
          if (buttons.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(children: buttons),
          ],
          if (!trip.sharingLocation)
            Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                t('dispatch.track.notSharing'),
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ),
        ],
      ),
    );
  }

  ButtonStyle _outlinedStyle() {
    return OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(44),
      foregroundColor: AppColors.navy,
      side: BorderSide(color: AppColors.inputBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String title;
  final String value;

  const _InfoRow({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

// Các điểm dừng và mốc tài xế đã bấm
class _StopsCard extends StatelessWidget {
  final List<TripStop> stops;

  const _StopsCard({required this.stops});

  @override
  Widget build(BuildContext context) {
    // Điểm đang tới = điểm đầu tiên chưa xong
    int currentIndex = -1;
    for (int i = 0; i < stops.length; i++) {
      if (!stops[i].isDone) {
        currentIndex = i;
        break;
      }
    }

    final List<Widget> children = <Widget>[
      Text(t('dispatch.track.milestonesTitle'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
    ];

    if (stops.isEmpty) {
      children.add(const SizedBox(height: 8));
      children.add(Text(t('dispatch.track.noStops'), style: TextStyle(color: AppColors.textMuted)));
    }

    for (int i = 0; i < stops.length; i++) {
      children.add(const SizedBox(height: 12));
      children.add(_StopBlock(stop: stops[i], isCurrent: i == currentIndex));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: _cardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

// Một điểm dừng: tên điểm, địa chỉ, liên hệ, rồi các mốc đã bấm
class _StopBlock extends StatelessWidget {
  final TripStop stop;
  final bool isCurrent;

  const _StopBlock({required this.stop, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    final String kindText = label(stopKindLabels, stop.kind);

    // Dòng phụ: địa chỉ · liên hệ
    final List<String> detailParts = <String>[];
    if (stop.address.isNotEmpty) {
      detailParts.add(stop.address);
    }
    if (stop.contactName.isNotEmpty || stop.contactPhone.isNotEmpty) {
      detailParts.add('${stop.contactName} ${stop.contactPhone}'.trim());
    }

    String title = t('dispatch.track.stopTitle', <String, Object?>{'sequence': stop.sequence, 'kind': kindText});
    Color titleColor = AppColors.text;
    if (isCurrent) {
      title = t('dispatch.track.stopCurrent', <String, Object?>{'sequence': stop.sequence, 'kind': kindText});
      titleColor = AppColors.navy;
    } else if (stop.isDone) {
      titleColor = AppColors.okText;
    }

    final List<Widget> rows = <Widget>[
      Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: titleColor)),
    ];
    if (detailParts.isNotEmpty) {
      rows.add(
        Text(detailParts.join(' · '), style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
      );
    }

    for (final TripMilestone milestone in stop.milestones) {
      String time = formatVietnamClock(milestone.recordedAt);
      String by = '';
      if (milestone.byName.isNotEmpty) {
        by = ' · ${milestone.byName}';
      }
      rows.add(const SizedBox(height: 6));
      rows.add(
        Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(color: AppColors.okText, shape: BoxShape.circle),
              child: const Icon(Icons.check, size: 13, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${label(tripMilestoneLabels, milestone.kind)} · $time$by',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      );
    }

    // Điểm chưa có mốc nào: nhắc là chưa bấm
    if (stop.milestones.isEmpty) {
      rows.add(const SizedBox(height: 6));
      rows.add(
        Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: isCurrent ? AppColors.navy : AppColors.inputBorder, width: 2),
              ),
            ),
            const SizedBox(width: 10),
            Text(t('dispatch.track.noMilestone'), style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
          ],
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}
