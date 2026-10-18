// N7: sơ đồ xếp hàng 2D của một chuyến (doc mục 3.8, màn N1-SoDo2D).
// Server vẽ sẵn SVG, app chỉ hiển thị và cho phóng to. Không tự tính gì.
import 'package:flutter/material.dart';
// SystemChrome, DeviceOrientation: xoay ngang màn hình khi xem toàn màn hình
import 'package:flutter/services.dart';
// Riverpod: ConsumerWidget, WidgetRef, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// flutter_svg (thư viện ngoài): vẽ chuỗi SVG thành hình
import 'package:flutter_svg/flutter_svg.dart';
// go_router: context.pushReplacement
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import 'plan_3d_api.dart';
import 'plan_3d_providers.dart';

class BlueprintScreen extends ConsumerWidget {
  final TripKey tripKey;

  const BlueprintScreen({super.key, required this.tripKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<TripBlueprint> blueprintValue = ref.watch(blueprintProvider(tripKey));

    // Dòng nhỏ dưới tiêu đề: "Xe 51C-900.01 · tỷ lệ 1:50"
    String subtitle = '';
    if (blueprintValue.hasValue) {
      final TripBlueprint blueprint = blueprintValue.value!;
      subtitle = 'Xe ${blueprint.plateNumber}';
      if (blueprint.scale.isNotEmpty) {
        subtitle = '$subtitle · tỷ lệ ${blueprint.scale}';
      }
    }

    // DefaultTabController (Flutter): giữ tab đang chọn cho TabBar và TabBarView bên dưới
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Sơ đồ xếp hàng'),
              if (subtitle.isNotEmpty)
                Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
          ),
        ),
        body: AsyncView<TripBlueprint>(
          value: blueprintValue,
          onRetry: () {
            ref.invalidate(blueprintProvider(tripKey));
          },
          builder: (TripBlueprint blueprint) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Băng vàng NHÁP: kiện nặng còn số liệu ước lượng
                if (blueprint.isDraft)
                  Container(
                    color: AppColors.warnBackground,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: 'NHÁP  ', style: TextStyle(fontWeight: FontWeight.w700)),
                          TextSpan(text: blueprint.draftReason),
                        ],
                      ),
                      style: const TextStyle(fontSize: 13, color: AppColors.warnText, height: 1.45),
                    ),
                  ),
                Container(
                  color: Colors.white,
                  child: const TabBar(
                    tabs: [
                      Tab(text: 'Mặt bằng'),
                      Tab(text: 'Mặt đứng'),
                    ],
                  ),
                ),
                // Hình chiếm khoảng 45% chiều cao màn
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.45,
                  child: TabBarView(
                    // Tắt vuốt ngang đổi tab, để vuốt dùng cho kéo hình
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      ZoomableSvg(svg: blueprint.topViewSvg),
                      ZoomableSvg(svg: blueprint.sideViewSvg),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Gợi ý để ngoài khung hình, không đè lên chữ của bản vẽ
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Kéo ngang để xem dọc thân xe · chụm hai ngón để phóng to · nút góc phải để xem toàn màn hình',
                          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                      ),
                      if (blueprint.notes.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'GHI CHÚ BẢN VẼ',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                      ...noteRows(blueprint.notes),
                      const SizedBox(height: 12),
                      // Nút cam (màu USP) sang màn 3D cùng chuyến
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
                        icon: const Icon(Icons.view_in_ar),
                        label: const Text('Xem 3D'),
                        onPressed: () {
                          // pushReplacement: thay màn 2D bằng 3D, bấm quay lại về màn trước đó (không lặp 2D, 3D)
                          context.pushReplacement(
                            '/orders/${tripKey.orderId}/plans/${tripKey.planId}/trips/${tripKey.tripId}/3d',
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// Mỗi ghi chú một dòng có dấu chấm đầu dòng
List<Widget> noteRows(List<String> notes) {
  final List<Widget> rows = <Widget>[];
  for (final String note in notes) {
    rows.add(
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text('•  $note', style: const TextStyle(fontSize: 14, color: AppColors.label, height: 1.5)),
      ),
    );
  }
  return rows;
}

// Tỷ lệ rộng / cao của bản vẽ, đọc từ viewBox="0 0 rộng cao". Không đọc được thì coi như 2,5 (bản vẽ dài, hẹp)
double svgAspectRatio(String svg) {
  // RegExp (Dart): tìm chuỗi theo mẫu. Lấy 4 số trong viewBox
  final RegExpMatch? match = RegExp(r'viewBox="\s*[-\d.]+[\s,]+[-\d.]+[\s,]+([\d.]+)[\s,]+([\d.]+)').firstMatch(svg);
  if (match == null) {
    return 2.5;
  }
  final double width = double.parse(match.group(1)!);
  final double height = double.parse(match.group(2)!);
  if (width <= 0 || height <= 0) {
    return 2.5;
  }
  return width / height;
}

// Một hình SVG phóng to, kéo được bằng ngón tay.
// Mở ra đã phóng vừa CHIỀU CAO khung (chữ đủ to để đọc), kéo ngang để xem dọc thân xe.
class ZoomableSvg extends StatelessWidget {
  final String svg;
  // false ở màn toàn màn hình (đang toàn màn hình rồi thì không cần nút)
  final bool showFullscreenButton;

  const ZoomableSvg({super.key, required this.svg, this.showFullscreenButton = true});

  @override
  Widget build(BuildContext context) {
    final double ratio = svgAspectRatio(svg);

    // LayoutBuilder (Flutter): biết khung được bao nhiêu chỗ rồi mới tính kích thước hình
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        double height = constraints.maxHeight;
        double width = height * ratio;
        // Khung rộng hơn hình (vd màn xoay ngang) thì cho hình vừa chiều ngang
        if (width < constraints.maxWidth) {
          width = constraints.maxWidth;
          height = width / ratio;
        }

        return Container(
          color: Colors.white,
          child: Stack(
            children: [
              // InteractiveViewer (Flutter): chụm hai ngón để phóng to/thu nhỏ, kéo để di chuyển.
              // constrained: false cho hình rộng hơn khung, kéo ngang được.
              InteractiveViewer(
                constrained: false,
                minScale: 0.2,
                maxScale: 6,
                boundaryMargin: const EdgeInsets.all(40),
                child: SizedBox(
                  width: width,
                  height: height,
                  // ponytail: flutter_svg vẽ nét đứt (stroke-dasharray) thành nét liền; cần đúng nét đứt thì đổi sang WebView loadHtmlString (doc mục 3.8)
                  child: SvgPicture.string(svg),
                ),
              ),
              if (showFullscreenButton)
                Positioned(
                  right: 8,
                  bottom: 4,
                  child: IconButton.filledTonal(
                    tooltip: 'Xem toàn màn hình',
                    icon: const Icon(Icons.fullscreen),
                    onPressed: () {
                      // rootNavigator: mở đè lên cả thanh tab dưới
                      Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute<void>(
                          builder: (BuildContext pageContext) {
                            return FullscreenSvgPage(svg: svg);
                          },
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// Bản vẽ toàn màn hình, điện thoại xoay ngang. Thoát thì trả lại hướng màn như cũ.
class FullscreenSvgPage extends StatefulWidget {
  final String svg;

  const FullscreenSvgPage({super.key, required this.svg});

  @override
  State<FullscreenSvgPage> createState() {
    return _FullscreenSvgPageState();
  }
}

class _FullscreenSvgPageState extends State<FullscreenSvgPage> {
  @override
  void initState() {
    super.initState();
    // SystemChrome (Flutter, gói services): ép xoay ngang, ẩn thanh trạng thái để bản vẽ chiếm hết màn
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // Danh sách rỗng = bỏ ép, điện thoại xoay theo cài đặt như bình thường
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          ZoomableSvg(svg: widget.svg, showFullscreenButton: false),
          Positioned(
            top: 8,
            left: 8,
            child: IconButton.filledTonal(
              tooltip: 'Thoát toàn màn hình',
              icon: const Icon(Icons.close),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ),
        ],
      ),
    );
  }
}
