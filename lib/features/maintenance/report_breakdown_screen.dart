// T6: tài xế báo hồng xe. Mở ra từ nút "Báo hồng xe" ở chi tiết chuyến của người 2.
// Chỉ báo được xe có mặt trong chuyến của mình, 0-5 ảnh, gửi kèm Idempotency-Key.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.pop
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/labels.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import 'maintenance_api.dart';
import 'maintenance_edit_screen.dart' show formatTimeRange;
import 'maintenance_providers.dart';
import 'widgets.dart';

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

  String? vehicleId;
  // Mặc định "Phải dừng xe" vì đó là mức nghiêm trọng hơn, tài xế muốn chạy tiếp thì đổi sang ô kia
  String severity = 'MustStop';
  final List<XFile> photos = <XFile>[];

  bool isSending = false;
  String? errorText;

  @override
  void dispose() {
    descriptionController.dispose();
    super.dispose();
  }

  Future<void> addPhoto() async {
    if (photos.length >= maxPhotos) {
      return;
    }
    final XFile? picked = await picker.pickImage(
      source: ImageSource.camera,
      // Thu nhỏ trước khi gửi: ảnh chụp từ máy rất nặng, mạng yếu dễ hụt
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      photos.add(picked);
    });
  }

  Future<void> send() async {
    final String description = descriptionController.text.trim();
    if (vehicleId == null) {
      setState(() {
        errorText = 'Chọn xe bị hỏng.';
      });
      return;
    }
    if (description.length < minDescriptionLength) {
      setState(() {
        errorText = 'Mô tả phải từ $minDescriptionLength ký tự trở lên.';
      });
      return;
    }

    setState(() {
      isSending = true;
      errorText = null;
    });
    try {
      await reportBreakdown(
        tripId: widget.tripId,
        vehicleId: vehicleId!,
        severity: severity,
        description: description,
        photoPaths: photos.map((XFile photo) => photo.path).toList(),
      );
      // Báo xong thì danh sách "bảo hồng của tôi" và danh sách quản lý đều đổi
      ref.invalidate(myBreakdownsProvider);
      ref.invalidate(breakdownsPageProvider);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã gửi báo hồng.')));
      context.pop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        isSending = false;
        errorText = errorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<MyTripBrief>> tripsValue = ref.watch(myTripsProvider);
    final MyTripBrief? trip = _pickTrip(tripsValue.value);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Báo hồng xe'),
        // Dòng phụ trên AppBar gọn chỉ đủ biết đang báo cho chuyến nào
        bottom: trip == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(22),
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Chuyến ${formatTimeRange(trip.startAt, trip.endAt)} · ${trip.orderCode}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ),
                ),
              ),
      ),
      body: AsyncView<List<MyTripBrief>>(
        value: tripsValue,
        onRetry: () {
          ref.invalidate(myTripsProvider);
        },
        builder: (List<MyTripBrief> trips) {
          if (trip == null) {
            return buildTripPicker(trips);
          }
          return buildForm(trip);
        },
      ),
    );
  }

  /// Chuyến đang báo. Không tìm thấy (mở nhầm chuyến, hoặc chuyến đã xong) thì để tài xế chọn lại.
  MyTripBrief? _pickTrip(List<MyTripBrief>? trips) {
    if (trips == null) {
      return null;
    }
    for (final MyTripBrief trip in trips) {
      if (trip.publicId == widget.tripId) {
        return trip;
      }
    }
    return null;
  }

  /// Danh sách chuyến để tài xế chọn. Cần cho lúc màn báo hồng mở bằng id không có trong danh sách.
  Widget buildTripPicker(List<MyTripBrief> trips) {
    if (trips.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'Bạn chưa có chuyến nào để báo hồng.\n'
                'Chuyến phải ở trạng thái "Đã chốt lịch" và có xe được gán.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              // Điều phối có thể vừa gán chuyến xong, bấm để tải lại danh sách
              OutlinedButton(
                onPressed: () {
                  ref.invalidate(myTripsProvider);
                },
                child: const Text('Tải lại'),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const SectionHeading('Chọn chuyến để báo hồng'),
        const SizedBox(height: 10),
        for (final MyTripBrief trip in trips)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(14),
            ),
            child: InkWell(
              onTap: () {
                context.push('/driver/trips/${trip.publicId}/breakdown');
              },
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          trip.orderCode,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatTimeRange(trip.startAt, trip.endAt),
                          style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget buildForm(MyTripBrief trip) {
    final List<Widget> children = <Widget>[];

    children.add(const SectionHeading('Xe nào bị hỏng?'));
    children.add(const SizedBox(height: 10));

    if (trip.vehicles.isEmpty) {
      children.add(const NoteText('Chuyến này chưa có xe nào được gán.'));
      children.add(const SizedBox(height: 20));
    } else {
      for (final TripVehicleOption vehicle in trip.vehicles) {
        // Xe mình đang lái thì ghi rõ ra cho khỏi chọn nhầm
        final bool isMine = vehicle.publicId == trip.myVehiclePublicId;
        children.add(
          ChoiceTile(
            title: vehicle.plateNumber.isEmpty ? vehicle.vehicleType : vehicle.plateNumber,
            subtitle: isMine ? '${vehicle.vehicleType} · xe bạn lái' : vehicle.vehicleType,
            isSelected: vehicleId == vehicle.publicId,
            onTap: () {
              setState(() {
                vehicleId = vehicle.publicId;
              });
            },
          ),
        );
      }
    }

    children.add(const SizedBox(height: 8));
    children.add(const SectionHeading('Mức độ'));
    children.add(const SizedBox(height: 10));
    children.add(
      ChoiceTile(
        title: label(breakdownSeverityLabels, 'MustStop'),
        subtitle: 'Không chạy tiếp được. Xe bị chặn nhận chuyến mới đến khi quản lý đóng báo.',
        isDanger: true,
        isSelected: severity == 'MustStop',
        onTap: () {
          setState(() {
            severity = 'MustStop';
          });
        },
      ),
    );
    children.add(
      ChoiceTile(
        title: label(breakdownSeverityLabels, 'CanContinue'),
        subtitle: 'Bao đờ quản lý biết và lên lịch sửa.',
        isSelected: severity == 'CanContinue',
        onTap: () {
          setState(() {
            severity = 'CanContinue';
          });
        },
      ),
    );

    children.add(const SizedBox(height: 8));
    children.add(const SectionHeading('Mô tả'));
    children.add(const SizedBox(height: 10));
    children.add(
      TextField(
        controller: descriptionController,
        enabled: !isSending,
        maxLines: 4,
        maxLength: maxDescriptionLength,
        inputFormatters: <TextInputFormatter>[
          LengthLimitingTextInputFormatter(maxDescriptionLength),
        ],
        decoration: const InputDecoration(hintText: 'Mô tả tình trạng, vị trí, âm thanh...'),
        onChanged: (String _) {
          // Đếm ký tự ngay khi gõ
          setState(() {});
        },
      ),
    );
    children.add(
      Align(
        alignment: Alignment.centerRight,
        child: NoteText(
          '${descriptionController.text.length} / $maxDescriptionLength ký tự '
          '(tối thiểu $minDescriptionLength)',
        ),
      ),
    );

    children.add(const SizedBox(height: 8));
    children.add(SectionHeading('Ảnh (tối đa $maxPhotos)'));
    children.add(const SizedBox(height: 10));
    children.add(PhotoRow(
      photos: photos,
      onAdd: isSending ? null : addPhoto,
      onRemove: isSending
          ? null
          : (int index) {
              setState(() {
                photos.removeAt(index);
              });
            },
    ));

    if (errorText != null) {
      children.add(const SizedBox(height: 16));
      children.add(ErrorBox(errorText!));
    }

    children.add(const SizedBox(height: 24));
    children.add(
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB42318)),
        onPressed: isSending ? null : send,
        child: Text(isSending ? 'Đang gửi...' : 'Gửi báo hồng'),
      ),
    );
    children.add(const SizedBox(height: 10));
    children.add(
      const NoteText(
        'Gửi kèm Idempotency-Key: mong yêu bấm lại không tạo hai báo.',
        color: AppColors.textMuted,
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: children,
    );
  }
}

/// Hàng ô ảnh: ảnh đã chọn (bấm xoá được) + ô "Thêm ảnh".
class PhotoRow extends StatelessWidget {
  final List<XFile> photos;
  final VoidCallback? onAdd;
  final void Function(int index)? onRemove;

  const PhotoRow({
    super.key,
    required this.photos,
    this.onAdd,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final bool isFull = photos.length >= maxPhotos;
    final List<Widget> tiles = <Widget>[];

    for (int index = 0; index < photos.length; index++) {
      tiles.add(
        Stack(
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                File(photos[index].path),
                width: 76,
                height: 76,
                fit: BoxFit.cover,
              ),
            ),
            if (onRemove != null)
              Positioned(
                top: 2,
                right: 2,
                child: GestureDetector(
                  onTap: () {
                    onRemove!(index);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close, size: 13, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // Chỉ còn ô thêm ảnh khi chưa đủ 5
    if (!isFull) {
      tiles.add(
        GestureDetector(
          onTap: onAdd,
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.inputBorder),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.add_a_photo_outlined, size: 20, color: AppColors.navy),
                SizedBox(height: 4),
                Text('Chụp ảnh', style: TextStyle(fontSize: 11, color: AppColors.navy, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
    }

    return Wrap(spacing: 10, runSpacing: 10, children: tiles);
  }
}