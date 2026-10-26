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
    if (vehicleId == null) return 'chọn xe';
    if (severity == null) return 'chọn mức hỏng';
    if (descriptionController.text.trim().length < minDescriptionLength) {
      return 'mô tả ít nhất $minDescriptionLength ký tự';
    }
    return null;
  }

  Future<void> choosePhotoSource() async {
    if (photos.length >= maxPhotos || isSending) {
      return;
    }
    final ImageSource? source = await showCupertinoModalPopup<ImageSource>(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: const Text('Thêm ảnh chỗ hỏng'),
        actions: <Widget>[
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(ImageSource.camera),
            child: const Text('Chụp ảnh'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(ImageSource.gallery),
            child: const Text('Chọn từ thư viện'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
      ),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(severity == 'MustStop'
            ? 'Đã báo hỏng. Điều phối sẽ gọi bạn; đừng chạy tiếp.'
            : 'Đã báo hỏng cho điều phối.'),
      ));
      close();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        isSending = false;
        errorText = error is ApiException && error.code == 'TRIP_NOT_EDITABLE'
            ? 'Ngoài giờ chuyến nên không báo qua app được: hãy gọi điều phối.'
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

    final List<Widget> slivers = <Widget>[
      CupertinoSliverNavigationBar(
        largeTitle: Text(widget.tripId.isEmpty ? 'Chọn chuyến' : 'Báo hỏng xe'),
        automaticallyImplyLeading: false,
        // Nút quay lại tròn kính như màn chi tiết chuyến
        leading: Padding(
          padding: EdgeInsets.zero,
          child: IosBackButton(onPressed: isSending ? null : close),
        ),
        padding: const EdgeInsetsDirectional.only(start: 8, end: 8),
        backgroundColor: IosColors.groupedBackground.withValues(alpha: 0.72),
        border: null,
        transitionBetweenRoutes: false,
      ),
    ];

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
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: IosColors.secondaryLabel)),
                CupertinoButton(onPressed: () => ref.invalidate(myTripsProvider), child: const Text('Thử lại')),
              ],
            ),
          ),
        ));
      },
    );

    // Chừa chỗ cho thanh gửi kính ở đáy
    slivers.add(SliverToBoxAdapter(
      child: SizedBox(height: MediaQuery.paddingOf(context).bottom + (trip == null ? 16 : 150)),
    ));

    return Scaffold(
      backgroundColor: IosColors.groupedBackground,
      body: IosBackground(
        glow: severity == 'CanContinue' ? IosColors.orange : IosColors.red,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: CustomScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                slivers: slivers,
              ),
            ),
            if (trip != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _SendBar(
                  missing: missingText(),
                  severity: severity,
                  busy: isSending,
                  onSend: () => send(trip),
                ),
              ),
          ],
        ),
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
                  const Icon(CupertinoIcons.cube_box_fill, size: 16, color: AppColors.navy),
                  const SizedBox(width: 8),
                  Text(
                    '${trip.orderCode} · ${formatTimeRange(trip.startAt, trip.endAt)}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.navy),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Xe
        if (trip.vehicles.isEmpty)
          const IosGroup(
            header: 'Xe nào hỏng?',
            children: <Widget>[
              Padding(
                padding: EdgeInsets.all(16),
                child: Text('Chuyến này chưa có xe nào được gán.', style: TextStyle(fontSize: 16, color: IosColors.secondaryLabel)),
              ),
            ],
          )
        else
          IosGroup(
            header: 'Xe nào hỏng?',
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
        const Padding(
          padding: EdgeInsets.fromLTRB(32, 0, 32, 7),
          child: Text('MỨC HỎNG', style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel, letterSpacing: 0.2)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: _SeverityTile(
                    title: 'Phải dừng xe',
                    hint: 'Không chạy tiếp được. Xe bị khóa nhận chuyến mới tới khi sửa xong.',
                    icon: Icons.dangerous_rounded,
                    color: IosColors.red,
                    selected: severity == 'MustStop',
                    onTap: isSending ? null : () => pickSeverity('MustStop'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SeverityTile(
                    title: 'Vẫn chạy được',
                    hint: 'Chạy tạm được. Báo để quản lý lên lịch sửa.',
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
          header: 'Hỏng gì, ở đâu?',
          footerWidget: Text(
            '$length/$maxDescriptionLength ký tự · ít nhất $minDescriptionLength',
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
              placeholder: 'VD: Rò dầu thủy lực ở chân chống sau bên phải',
              placeholderStyle: const TextStyle(fontSize: 16, color: IosColors.tertiaryLabel),
              style: const TextStyle(fontSize: 16, color: AppColors.text, height: 1.35),
              padding: const EdgeInsets.all(16),
              decoration: null,
              onChanged: (String _) => setState(() {}),
            ),
          ],
        ),

        // Ảnh
        IosGroup(
          header: 'Ảnh chỗ hỏng (${photos.length}/$maxPhotos)',
          footer: 'Ảnh rõ chỗ hỏng giúp quản lý chọn đúng thợ, đúng phụ tùng.',
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

        const Padding(
          padding: EdgeInsets.fromLTRB(32, 0, 32, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(CupertinoIcons.location_fill, size: 14, color: IosColors.secondaryLabel),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Vị trí hiện tại được gửi kèm (nếu lấy được) để điều phối biết xe nằm ở đâu.',
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
                  const Icon(CupertinoIcons.exclamationmark_circle_fill, size: 18, color: IosColors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(errorText!, style: const TextStyle(fontSize: 15, color: AppColors.errorText, height: 1.35)),
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
    final String subtitle = isMine ? '${vehicle.vehicleType} · xe bạn lái' : vehicle.vehicleType;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.white,
        child: InkWell(
          onTap: onTap,
          highlightColor: IosColors.fill,
          splashFactory: NoSplash.splashFactory,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
            child: Row(
              children: <Widget>[
                const IosIconBadge(icon: Icons.local_shipping_rounded, color: AppColors.navy),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text)),
                      Text(subtitle, style: const TextStyle(fontSize: 14, color: IosColors.secondaryLabel)),
                    ],
                  ),
                ),
                AnimatedOpacity(
                  opacity: selected ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: const Icon(CupertinoIcons.checkmark_alt, color: IosColors.blue, size: 24),
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
              color: selected ? Color.alphaBlend(color.withValues(alpha: 0.12), Colors.white) : Colors.white,
              border: Border.all(color: selected ? color : Colors.white, width: 2),
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
                        border: selected ? null : Border.all(color: const Color(0xFFC7C7CC), width: 1.5),
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
                Text(hint, style: const TextStyle(fontSize: 13, color: IosColors.secondaryLabel, height: 1.3)),
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
                  label: 'Bỏ ảnh ${index + 1}',
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
        label: 'Thêm ảnh chỗ hỏng',
        child: GestureDetector(
          onTap: onAdd,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: IosColors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(CupertinoIcons.camera_fill, size: 24, color: IosColors.blue),
                SizedBox(height: 4),
                Text('Thêm ảnh', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: IosColors.blue)),
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
                          'Còn thiếu: $missing',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14, color: IosColors.secondaryLabel),
                        ),
                      ),
              ),
              IosPillButton(
                label: busy ? 'Đang gửi...' : 'Gửi báo hỏng',
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
            const Icon(CupertinoIcons.cube_box, size: 52, color: IosColors.tertiaryLabel),
            const SizedBox(height: 12),
            const Text(
              'Chưa có chuyến để báo hỏng',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text),
            ),
            const SizedBox(height: 6),
            const Text(
              'Chuyến phải "Đã chốt lịch" và có xe được gán. Gấp thì gọi điều phối.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: IosColors.secondaryLabel, height: 1.4),
            ),
            CupertinoButton(onPressed: onReload, child: const Text('Tải lại')),
          ],
        ),
      );
    }

    return IosGroup(
      header: 'Báo cho chuyến nào?',
      footer: 'Chuyến đang chạy hoặc gần giờ nhất ở trên cùng.',
      dividerIndent: 62,
      children: <Widget>[
        for (final MyTripBrief trip in usable)
          Material(
            color: Colors.white,
            child: InkWell(
              highlightColor: IosColors.fill,
              splashFactory: NoSplash.splashFactory,
              onTap: () => context.pushReplacement('/driver/trips/${trip.publicId}/breakdown'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 11, 10, 11),
                child: Row(
                  children: <Widget>[
                    const IosIconBadge(icon: CupertinoIcons.cube_box_fill, color: AppColors.navy),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(trip.orderCode,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text)),
                          Text(
                            '${formatTimeRange(trip.startAt, trip.endAt)} · '
                            '${trip.vehicles.map((TripVehicleOption v) => v.plateNumber.isEmpty ? v.vehicleType : v.plateNumber).join(', ')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, color: IosColors.secondaryLabel),
                          ),
                        ],
                      ),
                    ),
                    const Icon(CupertinoIcons.chevron_forward, size: 18, color: IosColors.tertiaryLabel),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
