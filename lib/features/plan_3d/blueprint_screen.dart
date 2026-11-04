// N7: sơ đồ xếp hàng 2D của một chuyến (doc mục 3.8, màn N1-SoDo2D).
// Server vẽ sẵn SVG, app chỉ hiển thị và cho phóng to. Không tự tính gì.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
// SystemChrome, DeviceOrientation: xoay ngang màn hình khi xem toàn màn hình
import 'package:flutter/services.dart';
// Riverpod: ConsumerWidget, WidgetRef, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';
// flutter_svg (thư viện ngoài): vẽ chuỗi SVG thành hình
import 'package:flutter_svg/flutter_svg.dart';
// go_router: context.pushReplacement
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ios.dart';
import 'plan_3d_api.dart';
import 'plan_3d_providers.dart';

class BlueprintScreen extends ConsumerStatefulWidget {
  final TripKey tripKey;

  const BlueprintScreen({super.key, required this.tripKey});

  @override
  ConsumerState<BlueprintScreen> createState() => _BlueprintScreenState();
}

class _BlueprintScreenState extends ConsumerState<BlueprintScreen> {
  // 0: mặt bằng, 1: mặt đứng
  int view = 0;

  @override
  Widget build(BuildContext context) {
    final TripKey tripKey = widget.tripKey;
    final AsyncValue<TripBlueprint> blueprintValue = ref.watch(blueprintProvider(tripKey));
    final TripBlueprint? blueprint = blueprintValue.hasError ? null : blueprintValue.value;

    // Dòng nhỏ dưới tiêu đề: "Xe 51C-900.01 · tỷ lệ 1:50"
    String subtitle = '';
    if (blueprint != null) {
      subtitle = t('plan3d.vehicle', <String, Object?>{'plate': blueprint.plateNumber});
      if (blueprint.scale.isNotEmpty) {
        subtitle = '$subtitle · ${t('plan3d.scale', <String, Object?>{'scale': blueprint.scale})}';
      }
    }

    return IosPage(
      title: t('plan3d.blueprint.title'),
      trailing: IosGlassIconButton(
        icon: CupertinoIcons.cube,
        nativeSymbol: 'cube',
        tooltip: t('plan3d.view3d'),
        // pushReplacement: thay màn 2D bằng 3D, bấm quay lại về màn trước đó (không lặp 2D, 3D)
        onPressed: () => context.pushReplacement('/orders/${tripKey.orderId}/plans/${tripKey.planId}/trips/${tripKey.tripId}/3d'),
      ),
      slivers: blueprint == null
          ? <Widget>[
              SliverFillRemaining(
                hasScrollBody: false,
                child: AsyncView<TripBlueprint>(
                  value: blueprintValue,
                  onRetry: () => ref.invalidate(blueprintProvider(tripKey)),
                  builder: (TripBlueprint _) => const SizedBox.shrink(),
                ),
              ),
            ]
          : <Widget>[
              if (subtitle.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(subtitle, style: TextStyle(fontSize: 15, color: IosColors.secondaryLabel)),
                  ),
                ),
              // NHÁP: kiện nặng còn số liệu ước lượng
              if (blueprint.isDraft)
                SliverToBoxAdapter(
                  child: IosGroup(
                    children: <Widget>[
                      IosRow(
                        icon: CupertinoIcons.exclamationmark_triangle_fill,
                        iconColor: IosColors.orange,
                        title: t('plan3d.blueprint.draft'),
                        subtitle: blueprint.draftReason,
                        chevron: false,
                      ),
                    ],
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: CupertinoSlidingSegmentedControl<int>(
                      groupValue: view,
                      onValueChanged: (int? value) => setState(() => view = value ?? 0),
                      children: <int, Widget>{
                        0: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(t('plan3d.blueprint.topView'))),
                        1: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(t('plan3d.blueprint.sideView'))),
                      },
                    ),
                  ),
                ),
              ),
              // Hình chiếm khoảng 45% chiều cao màn, bo góc như một nhóm
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height * 0.45,
                      child: ZoomableSvg(key: ValueKey<int>(view), svg: view == 0 ? blueprint.topViewSvg : blueprint.sideViewSvg),
                    ),
                  ),
                ),
              ),
              // Gợi ý để ngoài khung hình, không đè lên chữ của bản vẽ
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 20),
                  child: Text(t('plan3d.blueprint.hint'), style: TextStyle(fontSize: 13, height: 1.35, color: IosColors.secondaryLabel)),
                ),
              ),
              if (blueprint.notes.isNotEmpty)
                SliverToBoxAdapter(
                  child: IosGroup(
                    header: t('plan3d.blueprint.notes'),
                    headerIcon: CupertinoIcons.doc_text_fill,
                    children: <Widget>[
                      for (final String note in blueprint.notes) IosRow(title: note, chevron: false),
                    ],
                  ),
                ),
            ],
    );
  }
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
          color: AppColors.surface,
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
                  right: 10,
                  bottom: 10,
                  child: IosGlassIconButton(
                    icon: CupertinoIcons.fullscreen,
                    nativeSymbol: 'arrow.up.left.and.arrow.down.right',
                    tooltip: t('plan3d.blueprint.fullscreen'),
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
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          ZoomableSvg(svg: widget.svg, showFullscreenButton: false),
          Positioned(
            top: 8,
            left: 8,
            child: IconButton.filledTonal(
              tooltip: t('plan3d.blueprint.exitFullscreen'),
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
