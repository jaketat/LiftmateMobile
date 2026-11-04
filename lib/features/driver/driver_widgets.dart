// Mảnh giao diện dùng chung của app tài xế
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/ios.dart';
import 'driver_api.dart';
import 'driver_providers.dart';
import 'location_tracker.dart';
import 'trip_logic.dart';
import '../../core/i18n.dart';

/// Gọi điện cho người liên hệ
Future<void> callPhone(BuildContext context, String? phone) async {
  final String digits = (phone ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
  if (digits.isEmpty) {
    return;
  }
  final bool opened = await launchUrl(Uri(scheme: 'tel', path: digits));
  if (!opened && context.mounted) {
    showIosToast(context, t('trip.callFailed', <String, Object?>{'phone': phone ?? ''}), isError: true);
  }
}

/// Dẫn đường tới một điểm bằng Google Maps (có tọa độ thì dùng tọa độ, không thì tìm theo địa chỉ)
/// Google Maps tính tuyến cho xe con nên phải hỏi trước: có thể đi vào đường cấm tải.
Future<void> navigateTo(BuildContext context, TripStop stop) async {
  final bool confirmed = await showIosConfirm(
    context,
    title: t('map.google.title'),
    message: t('map.google.message'),
    action: t('map.google.open'),
    destructive: false,
  );
  if (!confirmed || !context.mounted) {
    return;
  }
  final String destination = stop.hasCoordinates ? '${stop.latitude},${stop.longitude}' : stop.address;
  final Uri uri = Uri.https('www.google.com', '/maps/dir/', <String, String>{
    'api': '1',
    'destination': destination,
    'travelmode': 'driving',
  });
  final bool opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    showIosToast(context, t('map.openFailed'), isError: true);
  }
}

/// Viên trạng thái chia sẻ vị trí; bấm vào mở màn đồng ý / tắt (T7)
class SharingChip extends ConsumerWidget {
  const SharingChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ConsentState? consent = ref.watch(consentProvider).value;
    final TrackerState tracker = ref.watch(locationTrackerProvider);

    String text;
    Color dot;
    Color color;
    if (consent == null || !consent.accepted) {
      text = t('location.status.off');
      dot = AppColors.textMuted;
      color = AppColors.label;
    } else if (tracker.problem != null) {
      text = tracker.problem!;
      dot = AppColors.warnText;
      color = AppColors.warnText;
    } else if (tracker.running) {
      final DateTime? sent = tracker.lastSentAt;
      // Đang ghi hành trình (từ lúc tới điểm bốc) thì nói rõ để tài xế biết app vẫn gửi khi khóa máy
      text = tracker.recording
          ? (sent == null ? t('location.status.recording') : t('location.status.recordingAt', <String, Object?>{'time': clock(sent)}))
          : (sent == null ? t('location.status.sharing') : t('location.status.sharingAt', <String, Object?>{'time': clock(sent)}));
      if (tracker.offline && tracker.pending > 0) {
        text = t('location.status.offline', <String, Object?>{'count': tracker.pending});
      }
      dot = const Color(0xFF12B76A);
      color = AppColors.okText;
    } else {
      text = t('location.status.onIdle');
      dot = const Color(0xFF12B76A);
      color = AppColors.okText;
    }
    return GlassChip(
      text: text,
      dotColor: dot,
      textColor: color,
      onTap: () => context.push('/driver/location-consent'),
    );
  }
}

class RoleChip extends StatelessWidget {
  final String role;

  const RoleChip({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    final bool main = role == 'MainDriver';
    return IosPill(tEnum('crewRole', role), color: main ? AppColors.navy : const Color(0xFF8E8E93));
  }
}

/// Thẻ một chuyến trên sheet. [featured]: thẻ lớn của chuyến hôm nay, có dải "Tiếp theo".
class TripCard extends StatelessWidget {
  final MyTrip trip;
  final bool featured;
  final bool withDay;
  final VoidCallback onTap;

  const TripCard({super.key, required this.trip, required this.onTap, this.featured = false, this.withDay = false});

  @override
  Widget build(BuildContext context) {
    final List<TripStop> stops = trip.stops;
    final TripStop? first = stops.isEmpty ? null : stops.first;
    final TripStop? last = stops.length < 2 ? null : stops.last;
    final String? next = nextActionText(trip);
    final TripVehicle? vehicle = trip.myVehicle;
    final List<String> facts = <String>[
      if (vehicle != null) vehicle.displayName,
      if (trip.cargoKg != null && trip.cargoKg! > 0) formatKg(trip.cargoKg),
    ];
    final bool past = trip.endAt.isBefore(DateTime.now()) && trip.nextAction == null;
    final bool running = trip.trackingActive && next != null && !trip.startAt.isAfter(DateTime.now());

    final List<Widget> children = <Widget>[
      Row(
        children: <Widget>[
          Expanded(
            child: Text(
              tripTimeText(trip, withDay: withDay),
              style: TextStyle(
                fontSize: featured ? 22 : 18,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
                letterSpacing: -0.4,
              ),
            ),
          ),
          RoleChip(role: trip.myRole),
          Padding(
            padding: EdgeInsets.only(left: 6),
            child: Icon(CupertinoIcons.chevron_forward, size: 16, color: IosColors.tertiaryLabel),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        trip.customerName,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.25),
      ),
      const SizedBox(height: 2),
      Text(trip.orderCode, style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel)),
    ];

    if (first != null) {
      children.add(const SizedBox(height: 14));
      children.add(_StopsLine(first: first, last: last));
    }
    if (facts.isNotEmpty) {
      children.add(const SizedBox(height: 12));
      children.add(Row(
        children: <Widget>[
          Icon(CupertinoIcons.car_detailed, size: 15, color: IosColors.secondaryLabel),
          const SizedBox(width: 6),
          Expanded(
            child: Text(facts.join(' · '), style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel)),
          ),
        ],
      ));
    }
    if (docsDue(trip)) {
      children.add(DocsMissingPill(trip: trip));
    }
    if (next != null && !past) {
      final Color accent = running ? IosColors.green : IosColors.orange;
      children.add(const SizedBox(height: 12));
      children.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: <Widget>[
            Icon(
              running ? CupertinoIcons.location_north_fill : CupertinoIcons.clock_fill,
              size: 15,
              color: accent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                next,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: running ? AppColors.okText : AppColors.warmText),
              ),
            ),
          ],
        ),
      ));
    }

    return Opacity(
      opacity: past ? 0.6 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x140C2858), blurRadius: 18, offset: Offset(0, 6))],
        ),
        child: Material(
          color: AppColors.raised,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            highlightColor: IosColors.fill,
            splashFactory: NoSplash.splashFactory,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
            ),
          ),
        ),
      ),
    );
  }
}

class _StopsLine extends StatelessWidget {
  final TripStop first;
  final TripStop? last;

  const _StopsLine({required this.first, required this.last});

  Widget _dot(Color color) {
    return Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
  }

  // Một điểm dừng; đường nối chạy theo chiều cao địa chỉ (có thể hai dòng)
  Widget _stop(Color color, String address, {required bool connected}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Column(
            children: <Widget>[
              Padding(padding: const EdgeInsets.only(top: 4), child: _dot(color)),
              if (connected)
                Expanded(
                  child: Container(width: 2, margin: const EdgeInsets.only(top: 3, bottom: 1), color: AppColors.hairline),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: connected ? 10 : 0),
              child: Text(
                address,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: AppColors.text, height: 1.3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        // Chế độ tối màu nhấn là cam, trùng điểm giao: đổi sang xanh lá để phân biệt
        _stop(AppColors.isDark ? const Color(0xFF28A745) : AppColors.navy, first.address, connected: last != null),
        if (last != null) _stop(AppColors.orange, last!.address, connected: false),
      ],
    );
  }
}

/// Bộ lọc kiểu iOS (Hôm nay / Sắp tới / Đã qua): CupertinoSlidingSegmentedControl
class GlassSegmented extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  const GlassSegmented({super.key, required this.labels, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (useNativeControls) {
      // Vầng sáng theo vị trí ngón tay (mặc định của gói rất nhạt trên nền sáng) và nảy khi nhấn như iOS 26
      return IosPressBounce(
        child: lg.GlassSegmentedControl(
          useOwnLayer: true,
          quality: lg.GlassQuality.standard,
          glowColor: (AppColors.isDark ? Colors.white : AppColors.navy).withValues(alpha: 0.28),
          glowRadius: 2,
          selectedIndex: selected,
          onSegmentSelected: onChanged,
          segments: <lg.GlassSegment>[for (final String label in labels) lg.GlassSegment(label: label)],
        ),
      );
    }
    final Map<int, Widget> children = <int, Widget>{
      for (int index = 0; index < labels.length; index++)
        index: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Text(
            labels[index],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: index == selected ? FontWeight.w600 : FontWeight.w500,
              color: AppColors.text,
            ),
          ),
        ),
    };
    return SizedBox(
      width: double.infinity,
      child: CupertinoSlidingSegmentedControl<int>(
        groupValue: selected,
        backgroundColor: IosColors.fill,
        thumbColor: Colors.white,
        children: children,
        onValueChanged: (int? value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

class SheetSectionTitle extends StatelessWidget {
  final String text;

  const SheetSectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 13, letterSpacing: 0.2, color: IosColors.secondaryLabel),
      ),
    );
  }
}

/// Nút việc nhanh kiểu A trên canvas ("Nút tròn kính", như Camera / Control Center của iOS 26):
/// vòng tròn kính trắng 56, biểu tượng nét mảnh một màu navy (đỏ chỉ cho báo hỏng), chữ xám bên dưới.
/// Không bấm được thì mờ đi.
class GlassActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;

  GlassActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    Color? color,
  }) : color = color ?? AppColors.navy;

  // Đỏ đậm của iOS cho chữ / nét trên nền sáng (đủ tương phản hơn #FF3B30)
  static Color get danger => AppColors.isDark ? const Color(0xFFFF453A) : const Color(0xFFD70015);

  // Tên SF Symbol cho nút thật của iOS
  static final Map<IconData, String> _symbols = <IconData, String>{
    CupertinoIcons.list_bullet: 'list.bullet',
    CupertinoIcons.camera: 'camera',
    CupertinoIcons.exclamationmark_triangle: 'exclamationmark.triangle',
    CupertinoIcons.location_north: 'location.north',
    CupertinoIcons.phone: 'phone',
  };

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    final String? symbol = useNativeControls ? _symbols[icon] : null;
    final Widget flutterFace = Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[AppColors.glass.withValues(alpha: 0.72), AppColors.glass.withValues(alpha: 0.42)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: AppColors.isDark ? 0.15 : 0.95)),
        boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x1A0C2858), blurRadius: 14, offset: Offset(0, 4))],
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: 24),
    );
    return Expanded(
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label.replaceAll('\n', ' '),
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Opacity(
            opacity: enabled ? 1 : 0.35,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: <Widget>[
                  if (symbol == null)
                    flutterFace
                  else
                    NativeSwap(
                      native: () => NativeGlassButton(
                        symbol: symbol,
                        label: label.replaceAll('\n', ' '),
                        size: 56,
                        iconSize: 18,
                        foreground: color,
                        onPressed: onTap,
                      ),
                      fallback: flutterFace,
                    ),
                  const SizedBox(height: 7),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppColors.text, height: 1.2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------ Nhắc nộp ảnh hiện trường và biên bản (BR-DOC-008)
// Theo web (OrderActions.tsx, Slice 8 Q1): thiếu biên bản giao hàng thì chỉ NHẮC, không chặn chuyến.

/// Đã tới lúc nộp: đã dỡ hàng ở một điểm trả, hoặc đã xong mọi điểm; và chuyến còn cho gửi ảnh.
bool docsDue(MyTrip trip) {
  if (!trip.canUploadDocuments) return false;
  final bool unloaded = trip.milestones.any((TripMilestone m) => m.kind == 'Unloaded');
  final bool finished = trip.nextAction == null && trip.milestones.isNotEmpty;
  return unloaded || finished;
}

/// Số ảnh hiện trường / biên bản còn hiệu lực (bỏ ảnh điều phối đã loại)
({int field, int pod}) docCounts(List<TripDocument> docs) {
  int field = 0;
  int pod = 0;
  for (final TripDocument doc in docs) {
    if (doc.isVoided) continue;
    if (doc.documentType == 'POD') {
      pod++;
    } else {
      field++;
    }
  }
  return (field: field, pod: pod);
}

/// Thẻ nhắc nộp ảnh: hai dòng kiểm (ảnh hiện trường, biên bản giao hàng) + nút "Chụp ngay".
/// Đủ cả hai thì thu thành một dòng xanh "Đã nộp đủ" ([showWhenDone]) hoặc ẩn hẳn.
class DocsReminderCard extends ConsumerWidget {
  final MyTrip trip;
  // Trang chủ: ghi rõ chuyến nào
  final bool showTrip;
  final bool showWhenDone;

  const DocsReminderCard({super.key, required this.trip, this.showTrip = false, this.showWhenDone = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<TripDocument>? docs = ref.watch(tripDocumentsProvider(trip.publicId)).value;
    if (docs == null) return const SizedBox.shrink();
    final ({int field, int pod}) counts = docCounts(docs);
    final bool done = counts.field > 0 && counts.pod > 0;
    void open() => context.push('/driver/trips/${trip.publicId}/documents');

    if (done) {
      if (!showWhenDone) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: open,
            highlightColor: IosColors.fill,
            splashFactory: NoSplash.splashFactory,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: <Widget>[
                  Icon(CupertinoIcons.checkmark_seal_fill, color: IosColors.green, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t('trip.docs.submitted', <String, Object?>{'photos': counts.field, 'pods': counts.pod}),
                      style: TextStyle(fontSize: 15, color: AppColors.text),
                    ),
                  ),
                  Icon(CupertinoIcons.chevron_forward, size: 18, color: IosColors.tertiaryLabel),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget check(String text, int count) {
      final bool ok = count > 0;
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: <Widget>[
            Icon(
              ok ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
              size: 20,
              color: ok ? IosColors.green : IosColors.orange,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                ok
                    ? t('trip.docs.itemCount', <String, Object?>{'item': text, 'count': count})
                    : t('trip.docs.itemMissing', <String, Object?>{'item': text}),
                style: TextStyle(fontSize: 15, color: ok ? IosColors.secondaryLabel : AppColors.text),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: IosColors.orange.withValues(alpha: 0.55), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: IosColors.orange.withValues(alpha: 0.14), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Icon(CupertinoIcons.doc_text_viewfinder, size: 20, color: AppColors.warmText),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        t('trip.docs.title'),
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text),
                      ),
                      if (showTrip) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          '${trip.orderCode} · ${trip.customerName}',
                          style: TextStyle(fontSize: 14, color: IosColors.secondaryLabel, height: 1.3),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            check(t('trip.docs.fieldPhotos'), counts.field),
            check(t('trip.docs.pod'), counts.pod),
            const SizedBox(height: 14),
            IosPillButton(label: t('trip.docs.capture'), icon: CupertinoIcons.camera_fill, onPressed: open),
          ],
        ),
      ),
    );
  }
}

/// Viên nhỏ trên thẻ chuyến: "Thiếu biên bản" / "Thiếu ảnh" khi đã tới lúc nộp mà chưa đủ
class DocsMissingPill extends ConsumerWidget {
  final MyTrip trip;

  const DocsMissingPill({super.key, required this.trip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<TripDocument>? docs = ref.watch(tripDocumentsProvider(trip.publicId)).value;
    if (docs == null) return const SizedBox.shrink();
    final ({int field, int pod}) counts = docCounts(docs);
    final String? text = counts.pod == 0
        ? (counts.field == 0 ? t('trip.docs.missingBoth') : t('trip.docs.missingPod'))
        : (counts.field == 0 ? t('trip.docs.missingPhotos') : null);
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: <Widget>[
          Icon(CupertinoIcons.camera, size: 14, color: AppColors.warmText),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.warmText)),
        ],
      ),
    );
  }
}
