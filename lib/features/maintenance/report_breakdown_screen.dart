// T6: tài xế báo hỏng xe, kiểu iOS (Cupertino + Liquid Glass). Mở từ "Báo hỏng" ở trang chủ,
// chi tiết chuyến, hoặc tab Báo hỏng (chưa chọn chuyến thì chọn chuyến trước).
// Luật theo web (BreakdownDialog.tsx):
// - Chọn xe (mặc định xe mình lái), BẮT BUỘC chọn mức "Phải dừng xe" / "Vẫn chạy được", mô tả 10–1000 ký tự, 0–5 ảnh.
// - Idempotency-Key sinh MỘT lần khi mở màn: mạng yếu bấm gửi lại không tạo hai báo.
// - Kèm vị trí hiện tại nếu lấy được (không lấy được vẫn gửi).
// - Nút gửi bị khóa thì ghi rõ "Còn thiếu: ..." vì tài xế không rê chuột xem gợi ý được.
// - Ngoài giờ chuyến (TRIP_NOT_EDITABLE): bảo tài xế gọi điều phối.
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/call.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/ios.dart';
import '../driver/trip_detail_screen.dart' show currentPositionOrNull;
import 'maintenance_api.dart';
import 'maintenance_edit_screen.dart' show formatTimeRange;
import 'maintenance_providers.dart';

const int minDescriptionLength = 10;
const int maxDescriptionLength = 1000;
const int maxPhotos = 5;

class ReportBreakdownScreen extends ConsumerStatefulWidget {
  final String tripId;

  const ReportBreakdownScreen({super.key, required this.tripId});

  @override
  ConsumerState<ReportBreakdownScreen> createState() => _ReportBreakdownScreenState();
}

class _ReportBreakdownScreenState extends ConsumerState<ReportBreakdownScreen> {
  final TextEditingController descriptionController = TextEditingController();
  final ImagePicker picker = ImagePicker();
  final String idempotencyKey = const Uuid().v4();

  String? vehicleId;
  String? severity;
  final List<XFile> photos = <XFile>[];

  bool isSending = false;
  String? errorText;

  @override
  void dispose() {
    descriptionController.dispose();
    super.dispose();
  }

  void close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/driver/breakdowns');
    }
  }

  String? missingText() {
    if (vehicleId == null) return t('reportBreakdown.missingVehicle');
    if (severity == null) return t('reportBreakdown.missingSeverity');
    if (descriptionController.text.trim().length < minDescriptionLength) {
      return t('reportBreakdown.missingDescription', {'min': minDescriptionLength});
    }
    return null;
  }

  Future<void> choosePhotoSource() async {
    if (photos.length >= maxPhotos || isSending) {
      return;
    }
    final ImageSource? source = await showIosActionSheet<ImageSource>(
      context,
      title: t('reportBreakdown.addPhotoTitle'),
      options: <IosSheetOption<ImageSource>>[
        IosSheetOption<ImageSource>(ImageSource.camera, t('common.takePhoto')),
        IosSheetOption<ImageSource>(ImageSource.gallery, t('common.chooseFromLibrary')),
      ],
    );
    if (source == null) {
      return;
    }
    final int room = maxPhotos - photos.length;
    final List<XFile> picked = <XFile>[];
    // Thu nhỏ trước khi gửi: ảnh chụp từ máy rất nặng, mạng yếu dễ hụt
    if (source == ImageSource.gallery && room >= 2) {
      picked.addAll(await picker.pickMultiImage(maxWidth: 1600, imageQuality: 85, limit: room));
    } else {
      final XFile? one = await picker.pickImage(source: source, maxWidth: 1600, imageQuality: 85);
      if (one != null) picked.add(one);
    }
    if (!mounted || picked.isEmpty) {
      return;
    }
    setState(() {
      photos.addAll(picked.take(room));
    });
  }

  Future<void> send(MyTripBrief trip) async {
    if (missingText() != null || isSending) {
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      isSending = true;
      errorText = null;
    });
    try {
      final Position? position = await currentPositionOrNull();
      await reportBreakdown(
        tripId: trip.publicId,
        vehicleId: vehicleId!,
        severity: severity!,
        description: descriptionController.text.trim(),
        photoPaths: photos.map((XFile photo) => photo.path).toList(),
        latitude: position?.latitude,
        longitude: position?.longitude,
        idempotencyKey: idempotencyKey,
      );
      ref.invalidate(myBreakdownsProvider);
      ref.invalidate(breakdownsPageProvider);
      if (!mounted) {
        return;
      }
      showIosToast(context, severity == 'MustStop' ? t('reportBreakdown.sentMustStop') : t('reportBreakdown.sent'));
      close();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        isSending = false;
        errorText = error is ApiException && error.code == 'TRIP_NOT_EDITABLE'
            ? t('reportBreakdown.tripClosed')
            : errorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<MyTripBrief>> tripsValue = ref.watch(myTripsProvider);
    final MyTripBrief? trip = _findTrip(tripsValue.value);

    // Mặc định chọn xe mình lái (hoặc xe đầu tiên), như web
    if (trip != null && vehicleId == null && trip.vehicles.isNotEmpty) {
      final bool hasMine = trip.vehicles.any((TripVehicleOption v) => v.publicId == trip.myVehiclePublicId);
      vehicleId = hasMine ? trip.myVehiclePublicId : trip.vehicles.first.publicId;
    }

    final List<Widget> slivers = <Widget>[];

    tripsValue.when(
      data: (List<MyTripBrief> trips) {
        if (trip == null) {
          slivers.add(SliverToBoxAdapter(child: _TripPicker(trips: trips, onReload: () => ref.invalidate(myTripsProvider))));
        } else {
          slivers.add(SliverToBoxAdapter(child: _buildForm(trip)));
        }
      },
      loading: () {
        slivers.add(const SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.only(top: 80), child: CupertinoActivityIndicator(radius: 13)),
        ));
      },
      error: (Object error, StackTrace _) {
        slivers.add(SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
            child: Column(
              children: <Widget>[
                Text(errorMessage(error),
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: IosColors.secondaryLabel)),
                CupertinoButton(onPressed: () => ref.invalidate(myTripsProvider), child: Text(t('common.retry'))),
              ],
            ),
          ),
        ));
      },
    );


    return IosPage(
      title: widget.tripId.isEmpty ? t('reportBreakdown.chooseTripTitle') : t('reportBreakdown.title'),
      glow: severity == 'CanContinue' ? IosColors.orange : IosColors.red,
      // Nút quay lại tròn kính; đang gửi thì khoá
      onBack: isSending ? () {} : close,
      slivers: slivers,
      bottom: trip == null
          ? null
          : _SendBar(
              missing: missingText(),
              severity: severity,
              busy: isSending,
              onSend: () => send(trip),
            ),
    );
  }

  MyTripBrief? _findTrip(List<MyTripBrief>? trips) {
    if (trips == null || widget.tripId.isEmpty) {
      return null;
    }
    for (final MyTripBrief trip in trips) {
      if (trip.publicId == widget.tripId) {
        return trip;
      }
    }
    return null;
  }

  Widget _buildForm(MyTripBrief trip) {
    final int length = descriptionController.text.trim().length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Chuyến đang báo
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Glass(
              opacity: 0.55,
              shadow: false,
              borderRadius: BorderRadius.circular(999),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(CupertinoIcons.cube_box_fill, size: 16, color: AppColors.navy),
                  const SizedBox(width: 8),
                  Text(
                    '${trip.orderCode} · ${formatTimeRange(trip.startAt, trip.endAt)}',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.navy),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Xe
        if (trip.vehicles.isEmpty)
          IosGroup(
            header: t('reportBreakdown.vehicle'),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(t('reportBreakdown.noVehicle'), style: TextStyle(fontSize: 16, color: IosColors.secondaryLabel)),
              ),
            ],
          )
        else
          IosGroup(
            header: t('reportBreakdown.vehicle'),
            dividerIndent: 62,
            children: <Widget>[
              for (final TripVehicleOption vehicle in trip.vehicles)
                _VehicleRow(
                  vehicle: vehicle,
                  isMine: vehicle.publicId == trip.myVehiclePublicId,
                  selected: vehicleId == vehicle.publicId,
                  onTap: isSending
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          setState(() => vehicleId = vehicle.publicId);
                        },
                ),
            ],
          ),

        // Mức hỏng
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 7),
          child: Text(
            t('reportBreakdown.severity').toUpperCase(),
            style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel, letterSpacing: 0.2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: _SeverityTile(
                    title: tEnum('breakdownSeverity', 'MustStop'),
                    hint: t('reportBreakdown.mustStopHint'),
                    icon: Icons.dangerous_rounded,
                    color: IosColors.red,
                    selected: severity == 'MustStop',
                    onTap: isSending ? null : () => pickSeverity('MustStop'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SeverityTile(
                    title: tEnum('breakdownSeverity', 'CanContinue'),
                    hint: t('reportBreakdown.canContinueHint'),
                    icon: Icons.warning_rounded,
                    color: IosColors.orange,
                    selected: severity == 'CanContinue',
                    onTap: isSending ? null : () => pickSeverity('CanContinue'),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Mô tả
        IosGroup(
          header: t('reportBreakdown.description'),
          footerWidget: Text(
            t('reportBreakdown.charCount', {'count': length, 'max': maxDescriptionLength, 'min': minDescriptionLength}),
            style: TextStyle(
              fontSize: 13,
              color: length > 0 && length < minDescriptionLength ? IosColors.red : IosColors.secondaryLabel,
            ),
          ),
          children: <Widget>[
            CupertinoTextField(
              controller: descriptionController,
              enabled: !isSending,
              minLines: 4,
              maxLines: 8,
              maxLength: maxDescriptionLength,
              textCapitalization: TextCapitalization.sentences,
              placeholder: t('reportBreakdown.descriptionPlaceholder'),
              placeholderStyle: TextStyle(fontSize: 16, color: IosColors.tertiaryLabel),
              style: TextStyle(fontSize: 16, color: AppColors.text, height: 1.35),
              padding: const EdgeInsets.all(16),
              decoration: null,
              onChanged: (String _) => setState(() {}),
            ),
          ],
        ),

        // Ảnh
        IosGroup(
          header: t('reportBreakdown.photos', {'count': photos.length, 'max': maxPhotos}),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(12),
              child: _PhotoGrid(
                photos: photos,
                onAdd: isSending ? null : choosePhotoSource,
                onRemove: isSending ? null : (int index) => setState(() => photos.removeAt(index)),
              ),
            ),
          ],
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(CupertinoIcons.location_fill, size: 14, color: IosColors.secondaryLabel),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  t('reportBreakdown.locationNote'),
                  style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel, height: 1.35),
                ),
              ),
            ],
          ),
        ),

        if (errorText != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: IosColors.red.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(CupertinoIcons.exclamationmark_circle_fill, size: 18, color: IosColors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(errorText!, style: TextStyle(fontSize: 15, color: AppColors.errorText, height: 1.35)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void pickSeverity(String value) {
    HapticFeedback.selectionClick();
    setState(() => severity = value);
  }
}

/// Một dòng xe, dấu tích xanh bên phải khi chọn (như danh sách chọn của iOS)
class _VehicleRow extends StatelessWidget {
  final TripVehicleOption vehicle;
  final bool isMine;
  final bool selected;
  final VoidCallback? onTap;

  const _VehicleRow({required this.vehicle, required this.isMine, required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) {
    final String title = vehicle.plateNumber.isEmpty ? vehicle.vehicleType : vehicle.plateNumber;
    final String subtitle = isMine ? t('reportBreakdown.yourVehicle', {'type': vehicle.vehicleType}) : vehicle.vehicleType;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: AppColors.surface,
        child: InkWell(
          onTap: onTap,
          highlightColor: IosColors.fill,
          splashFactory: NoSplash.splashFactory,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
            child: Row(
              children: <Widget>[
                IosIconBadge(icon: Icons.local_shipping_rounded, color: AppColors.navy),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text)),
                      Text(subtitle, style: TextStyle(fontSize: 14, color: IosColors.secondaryLabel)),
                    ],
                  ),
                ),
                AnimatedOpacity(
                  opacity: selected ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(CupertinoIcons.checkmark_alt, color: IosColors.blue, size: 24),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ô mức hỏng: kính trắng; khi chọn thì nhuộm màu, viền màu, dấu tích góc phải
class _SeverityTile extends StatelessWidget {
  final String title;
  final String hint;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  const _SeverityTile({
    required this.title,
    required this.hint,
    required this.icon,
    required this.color,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$title. $hint',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedScale(
          scale: selected ? 1.0 : 0.98,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: selected ? Color.alphaBlend(color.withValues(alpha: 0.12), AppColors.surface) : Colors.white,
              border: Border.all(color: selected ? color : AppColors.surface, width: 2),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: selected ? color.withValues(alpha: 0.22) : const Color(0x0F000000),
                  blurRadius: selected ? 18 : 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    IosIconBadge(icon: icon, color: color, size: 34),
                    const Spacer(),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? color : Colors.transparent,
                        border: selected ? null : Border.all(color: AppColors.control, width: 1.5),
                      ),
                      child: selected ? const Icon(Icons.check_rounded, size: 15, color: Colors.white) : null,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: selected ? color : AppColors.text),
                ),
                const SizedBox(height: 3),
                Text(hint, style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel, height: 1.3)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lưới ảnh: ảnh đã chọn (nút xóa góc) + ô "Thêm ảnh" khi chưa đủ 5
class _PhotoGrid extends StatelessWidget {
  final List<XFile> photos;
  final VoidCallback? onAdd;
  final void Function(int index)? onRemove;

  const _PhotoGrid({required this.photos, this.onAdd, this.onRemove});

  @override
  Widget build(BuildContext context) {
    const double size = 78;
    final List<Widget> tiles = <Widget>[];
    for (int index = 0; index < photos.length; index++) {
      tiles.add(SizedBox(
        width: size,
        height: size,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(File(photos[index].path), fit: BoxFit.cover),
              ),
            ),
            if (onRemove != null)
              Positioned(
                top: 4,
                right: 4,
                child: Semantics(
                  button: true,
                  label: t('reportBreakdown.removePhoto', {'number': index + 1}),
                  child: GestureDetector(
                    onTap: () => onRemove!(index),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1),
                      ),
                      child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ));
    }
    if (photos.length < maxPhotos) {
      tiles.add(Semantics(
        button: true,
        label: t('reportBreakdown.addPhotoTitle'),
        child: GestureDetector(
          onTap: onAdd,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: IosColors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(CupertinoIcons.camera_fill, size: 24, color: IosColors.blue),
                const SizedBox(height: 4),
                Text(
                  t('reportBreakdown.addPhoto'),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: IosColors.blue),
                ),
              ],
            ),
          ),
        ),
      ));
    }
    return Wrap(spacing: 10, runSpacing: 10, children: tiles);
  }
}

/// Thanh kính nổi ở đáy: dòng "Còn thiếu: ..." và nút gửi (đỏ khi phải dừng xe)
class _SendBar extends StatelessWidget {
  final String? missing;
  final String? severity;
  final bool busy;
  final VoidCallback onSend;

  const _SendBar({required this.missing, required this.severity, required this.busy, required this.onSend});

  @override
  Widget build(BuildContext context) {
    final Color color = severity == 'CanContinue' ? AppColors.navy : IosColors.red;
    // Thẻ kính nổi ngay trên thanh tab (SafeArea đã tính chiều cao thanh tab)
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Glass(
          opacity: 0.62,
          borderRadius: BorderRadius.circular(30),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                child: missing == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          t('reportBreakdown.missing', {'item': missing}),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: IosColors.secondaryLabel),
                        ),
                      ),
              ),
              IosPillButton(
                label: busy ? t('common.sending') : t('reportBreakdown.send'),
                icon: CupertinoIcons.paperplane_fill,
                color: color,
                busy: busy,
                onPressed: missing == null ? onSend : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chưa chọn chuyến: danh sách chuyến có xe, gần giờ hiện tại nhất lên đầu
class _TripPicker extends StatelessWidget {
  final List<MyTripBrief> trips;
  final VoidCallback onReload;

  const _TripPicker({required this.trips, required this.onReload});

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final List<MyTripBrief> usable = trips.where((MyTripBrief t) => t.vehicles.isNotEmpty).toList()
      ..sort((MyTripBrief a, MyTripBrief b) {
        int distance(MyTripBrief t) {
          final DateTime start = DateTime.parse(t.startAt).toLocal();
          final DateTime end = DateTime.parse(t.endAt).toLocal();
          if (!now.isBefore(start) && !now.isAfter(end)) return 0;
          return (now.isBefore(start) ? start.difference(now) : now.difference(end)).inMinutes.abs();
        }

        return distance(a).compareTo(distance(b));
      });

    if (usable.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(40, 32, 40, 0),
        child: Column(
          children: <Widget>[
            Icon(CupertinoIcons.cube_box, size: 52, color: IosColors.tertiaryLabel),
            const SizedBox(height: 12),
            Text(
              t('reportBreakdown.noTripsTitle'),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text),
            ),
            const SizedBox(height: 6),
            Text(
              t('reportBreakdown.noTripsMessage'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: IosColors.secondaryLabel, height: 1.4),
            ),
            CupertinoButton(onPressed: onReload, child: Text(t('common.reload'))),
          ],
        ),
      );
    }

    return IosGroup(
      header: t('reportBreakdown.chooseTrip'),
      dividerIndent: 62,
      children: <Widget>[
        for (final MyTripBrief trip in usable)
          Material(
            color: AppColors.surface,
            child: InkWell(
              highlightColor: IosColors.fill,
              splashFactory: NoSplash.splashFactory,
              onTap: () => context.pushReplacement('/driver/trips/${trip.publicId}/breakdown'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 11, 10, 11),
                child: Row(
                  children: <Widget>[
                    IosIconBadge(icon: CupertinoIcons.cube_box_fill, color: AppColors.navy),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(trip.orderCode,
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text)),
                          Text(
                            '${formatTimeRange(trip.startAt, trip.endAt)} · '
                            '${trip.vehicles.map((TripVehicleOption v) => v.plateNumber.isEmpty ? v.vehicleType : v.plateNumber).join(', ')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, color: IosColors.secondaryLabel),
                          ),
                        ],
                      ),
                    ),
                    Icon(CupertinoIcons.chevron_forward, size: 18, color: IosColors.tertiaryLabel),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
