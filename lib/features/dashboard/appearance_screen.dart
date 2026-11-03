// Cài đặt giao diện: chọn nguồn ảnh bìa trang chủ. Mặc định, Bing đổi mỗi ngày, hoặc ảnh tự tải.
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/ios.dart';
import '../auth/session_provider.dart';
import 'bing_wallpaper.dart';
import 'home_cover.dart';

class AppearanceScreen extends ConsumerStatefulWidget {
  const AppearanceScreen({super.key});

  @override
  ConsumerState<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends ConsumerState<AppearanceScreen> {
  HomeCoverSource source = HomeCoverSource.standard;
  File? customImage;
  BingCover? bing;
  bool bingLoading = false;

  String? get userId {
    final String? id = ref.read(sessionProvider).value?.userId;
    return id == null || id.isEmpty ? null : id;
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final String? id = userId;
    if (id == null) return;
    final HomeCoverSource saved = await HomeCoverStore.source(id);
    final File? file = await HomeCoverStore.customFile(id);
    final BingCover? cached = await BingWallpaper.cached();
    if (!mounted) return;
    setState(() {
      source = saved;
      customImage = file;
      bing = cached;
    });
    // Xem trước đúng ảnh hôm nay, dù đang không chọn Bing
    refreshBing(showError: false);
  }

  Future<bool> refreshBing({required bool showError}) async {
    if (mounted) setState(() => bingLoading = true);
    try {
      final BingCover? latest = await BingWallpaper.refresh();
      if (mounted) {
        setState(() {
          bing = latest ?? bing;
          bingLoading = false;
        });
      }
      return latest != null;
    } catch (error) {
      debugPrint('Không tải được ảnh Bing: $error');
      if (mounted) setState(() => bingLoading = false);
      if (bing != null) return true;
      if (showError && mounted) showIosToast(context, t('appearance.bingFailed'), isError: true);
      return false;
    }
  }

  Future<void> choose(HomeCoverSource value) async {
    final String? id = userId;
    if (id == null) return;
    setState(() => source = value);
    await HomeCoverStore.setSource(id, value);
  }

  Future<void> chooseBing() async {
    if (bing != null || await refreshBing(showError: true)) await choose(HomeCoverSource.bing);
  }

  Future<void> pickCustom() async {
    final String? id = userId;
    if (id == null) return;
    final ImageSource? from = await showIosActionSheet<ImageSource>(
      context,
      title: t('appearance.custom'),
      message: t('appearance.customNote'),
      options: <IosSheetOption<ImageSource>>[
        IosSheetOption<ImageSource>(ImageSource.gallery, t('common.chooseFromLibrary')),
        IosSheetOption<ImageSource>(ImageSource.camera, t('common.takePhoto')),
      ],
    );
    if (from == null || !mounted) return;
    try {
      // Giới hạn cạnh dài: đủ nét cho ảnh bìa, giải mã không tốn nhiều bộ nhớ
      final XFile? file = await ImagePicker().pickImage(source: from, maxWidth: 1800, maxHeight: 1800, imageQuality: 85);
      if (file == null) return;
      final File saved = await HomeCoverStore.saveCustom(id, file.path);
      if (!mounted) return;
      setState(() => customImage = saved);
      await choose(HomeCoverSource.custom);
    } catch (error) {
      debugPrint('Không đổi được ảnh bìa: $error');
      if (mounted) showIosToast(context, t('appearance.customFailed'), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final File? customPreview = customImage;
    final BingCover? bingPreview = bing;
    return IosPage(
      title: t('appearance.title'),
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 16, 8),
            child: Text(t('appearance.coverHeader').toUpperCase(), style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel, letterSpacing: 0.2)),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: _CoverTile(
                    label: t('appearance.standard'),
                    selected: source == HomeCoverSource.standard,
                    onTap: () => choose(HomeCoverSource.standard),
                    // Mờ dần phần dưới như trên trang chủ thật, nếu không ô chỉ thấy một mảng đồi trơn
                    preview: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        CustomPaint(painter: DefaultCoverPainter(dark: AppColors.isDark)),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: const <double>[0.46, 0.85],
                              colors: <Color>[AppColors.surface.withValues(alpha: 0), AppColors.surface],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CoverTile(
                    label: t('appearance.bing'),
                    selected: source == HomeCoverSource.bing,
                    onTap: chooseBing,
                    preview: bingPreview != null
                        ? Image.file(bingPreview.image, fit: BoxFit.cover, cacheHeight: 500)
                        : Center(
                            child: bingLoading
                                ? const CupertinoActivityIndicator()
                                : Icon(CupertinoIcons.cloud_download, size: 30, color: IosColors.secondaryLabel),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CoverTile(
                    label: t('appearance.custom'),
                    selected: source == HomeCoverSource.custom,
                    onTap: () => customPreview == null ? pickCustom() : choose(HomeCoverSource.custom),
                    preview: customPreview != null
                        ? Image.file(customPreview, fit: BoxFit.cover, cacheHeight: 500, gaplessPlayback: true)
                        : Center(child: Icon(CupertinoIcons.photo_on_rectangle, size: 30, color: IosColors.secondaryLabel)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: IosGroup(
            footer: source == HomeCoverSource.bing
                ? <String>[t('appearance.bingNote'), if ((bingPreview?.copyright ?? '').isNotEmpty) bingPreview!.copyright].join('\n')
                : source == HomeCoverSource.custom
                    ? t('appearance.customNote')
                    : t('appearance.standardNote'),
            children: <Widget>[
              IosRow(
                icon: CupertinoIcons.photo_fill,
                iconColor: const Color(0xFF8E8E93),
                title: customPreview == null ? t('appearance.upload') : t('appearance.uploadOther'),
                onTap: pickCustom,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CoverTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget preview;

  const _CoverTile({required this.label, required this.selected, required this.onTap, required this.preview});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: IosPressBounce(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(
            children: <Widget>[
              AspectRatio(
                aspectRatio: 0.58,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: ColoredBox(color: AppColors.surface, child: preview),
                    ),
                    if (selected) ...<Widget>[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.navy, width: 3),
                        ),
                      ),
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
                          child: const Icon(CupertinoIcons.checkmark_alt, size: 16, color: Colors.white),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: AppColors.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
