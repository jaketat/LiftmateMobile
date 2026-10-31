// Khối giao diện kiểu iOS (Cupertino) cho app tài xế: nền nhóm xám nhạt có quầng màu để lớp kính
// nổi lên, nhóm ô bo góc "inset grouped" như Cài đặt của iPhone, tiêu đề nhóm chữ hoa nhỏ.
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../i18n.dart';
import 'glass.dart';

/// Màu hệ thống của iOS (light)
class IosColors {
  static const Color groupedBackground = Color(0xFFF2F2F7);
  static const Color separator = Color(0x4D3C3C43);
  static const Color secondaryLabel = Color(0x993C3C43);
  static const Color tertiaryLabel = Color(0x4D3C3C43);
  static const Color red = Color(0xFFFF3B30);
  static const Color orange = Color(0xFFFF9500);
  static const Color green = Color(0xFF34C759);
  static const Color blue = Color(0xFF007AFF);
  static const Color fill = Color(0x1F787880);
}

/// Nền xám nhóm có hai quầng màu mờ ở trên: kính trong suốt cần thứ gì phía sau mới thấy được.
class IosBackground extends StatelessWidget {
  final Widget child;
  final Color glow;
  // Nền xám trơn như Cài đặt của iPhone (không quầng màu)
  final bool plain;

  const IosBackground({super.key, required this.child, this.glow = IosColors.red, this.plain = false});

  @override
  Widget build(BuildContext context) {
    if (plain) {
      return ColoredBox(color: IosColors.groupedBackground, child: child);
    }
    return ColoredBox(
      color: IosColors.groupedBackground,
      child: Stack(
        children: <Widget>[
          Positioned(
            top: -120,
            right: -80,
            child: _Blob(color: glow.withValues(alpha: 0.16), size: 320),
          ),
          Positioned(
            top: 60,
            left: -120,
            child: _Blob(color: AppColors.navy.withValues(alpha: 0.10), size: 300),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final Color color;
  final double size;

  const _Blob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: <Color>[color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}

/// Nhóm ô kiểu "inset grouped": tiêu đề chữ hoa nhỏ, khối trắng bo 16, đường kẻ mảnh giữa các ô.
class IosGroup extends StatelessWidget {
  final String? header;
  final String? footer;
  final Widget? footerWidget;
  final List<Widget> children;
  // Đường kẻ bắt đầu sau biểu tượng (iOS lùi đường kẻ vào bằng phần chữ)
  final double dividerIndent;

  const IosGroup({
    super.key,
    this.header,
    this.footer,
    this.footerWidget,
    required this.children,
    this.dividerIndent = 16,
  });

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    for (int index = 0; index < children.length; index++) {
      if (index > 0) {
        rows.add(Padding(
          padding: EdgeInsets.only(left: dividerIndent),
          child: Container(height: 0.5, color: IosColors.separator),
        ));
      }
      rows.add(children[index]);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
              child: Text(
                header!.toUpperCase(),
                style: const TextStyle(fontSize: 13, color: IosColors.secondaryLabel, letterSpacing: 0.2),
              ),
            ),
          ClipRRect(
            // Bo góc lớn như nhóm ô của iOS 26
            borderRadius: BorderRadius.circular(24),
            child: ColoredBox(
              color: Colors.white,
              child: Column(mainAxisSize: MainAxisSize.min, children: rows),
            ),
          ),
          if (footerWidget != null || footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
              child: footerWidget ??
                  Text(
                    footer!,
                    style: const TextStyle(fontSize: 13, color: IosColors.secondaryLabel, height: 1.35),
                  ),
            ),
        ],
      ),
    );
  }
}

/// Ô vuông bo góc màu đặc chứa biểu tượng trắng, như biểu tượng trong Cài đặt của iPhone.
class IosIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const IosIconBadge({super.key, required this.icon, required this.color, this.size = 30});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.26),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color.lerp(color, Colors.white, 0.18)!, color],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white, size: size * 0.6),
    );
  }
}

/// Nhãn trạng thái dạng viên thuốc, nền nhạt cùng màu chữ
class IosPill extends StatelessWidget {
  final String text;
  final Color color;

  const IosPill(this.text, {super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

/// Nút chính dạng viên thuốc cao 54 (kiểu nút lớn của iOS 26)
class IosPillButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final VoidCallback? onPressed;
  final bool busy;

  const IosPillButton({
    super.key,
    required this.label,
    this.icon,
    this.color = AppColors.navy,
    this.onPressed,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null && !busy;
    return Semantics(
      button: true,
      enabled: enabled,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: enabled ? onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 54,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: enabled
                  ? <Color>[Color.lerp(color, Colors.white, 0.12)!, color]
                  : <Color>[const Color(0xFFD1D1D6), const Color(0xFFC7C7CC)],
            ),
            boxShadow: enabled
                ? <BoxShadow>[BoxShadow(color: color.withValues(alpha: 0.30), blurRadius: 16, offset: const Offset(0, 6))]
                : null,
          ),
          alignment: Alignment.center,
          child: busy
              ? const CupertinoActivityIndicator(color: Colors.white)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (icon != null) ...<Widget>[
                      Icon(icon, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      label,
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Trang kiểu iOS: tiêu đề lớn co lại khi cuộn (thanh trên kính mờ), nút quay lại tròn kính khi có màn trước,
/// nền nhóm có quầng màu, kéo xuống để tải lại (nếu có onRefresh), chừa chỗ cho thanh tab kính ở đáy.
/// Làm mờ tăng dần (progressive blur) như iOS 26: sát mép mờ nhiều, xa mép trong dần, không có đường cắt.
/// Ghép nhiều lớp làm mờ chồng nhau, lớp càng gần mép càng phủ hẹp và mờ mạnh; thêm lớp màu nền mờ dần cho chữ phía trên dễ đọc.
class ProgressiveBlur extends StatelessWidget {
  final double height;
  // true: mép trên (dưới thanh tiêu đề); false: mép dưới (sau thanh tab)
  final bool fromTop;
  final double maxSigma;
  final Color tint;
  final double tintOpacity;
  static const int steps = 6;

  const ProgressiveBlur({
    super.key,
    required this.height,
    this.fromTop = true,
    this.maxSigma = 14,
    this.tint = IosColors.groupedBackground,
    this.tintOpacity = 0.75,
  });

  @override
  Widget build(BuildContext context) {
    // height = double.infinity: lấp đầy chỗ cha cho (vd Positioned.fill)
    if (!height.isFinite) {
      return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) => ProgressiveBlur(
          height: constraints.maxHeight,
          fromTop: fromTop,
          maxSigma: maxSigma,
          tint: tint,
          tintOpacity: tintOpacity,
        ),
      );
    }
    final List<Widget> layers = <Widget>[];
    // Android không làm mờ: chỉ còn lớp màu mờ dần, đậm hơn để chữ cuộn phía sau không đè lên thanh trên
    final double tintAlpha = glassBlurEnabled ? tintOpacity : (tintOpacity * 1.25).clamp(0.0, 1.0);
    if (!glassBlurEnabled && tintOpacity == 0) {
      return const SizedBox.shrink();
    }
    for (int index = 0; glassBlurEnabled && index < steps; index++) {
      // Lớp 0 phủ hết chiều cao, mờ nhẹ; lớp sau phủ hẹp dần về phía mép và mờ thêm
      final double cover = height * (1 - index / steps);
      final double sigma = maxSigma / steps * (index + 1) * 0.55;
      layers.add(Positioned(
        left: 0,
        right: 0,
        top: fromTop ? 0 : null,
        bottom: fromTop ? null : 0,
        height: cover,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: const SizedBox.expand(),
          ),
        ),
      ));
    }
    layers.add(Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: fromTop ? Alignment.topCenter : Alignment.bottomCenter,
            end: fromTop ? Alignment.bottomCenter : Alignment.topCenter,
            colors: <Color>[
              tint.withValues(alpha: tintAlpha),
              tint.withValues(alpha: tintAlpha * 0.45),
              tint.withValues(alpha: 0),
            ],
            stops: const <double>[0, 0.5, 1],
          ),
        ),
      ),
    ));
    return IgnorePointer(child: SizedBox(height: height, child: Stack(children: layers)));
  }
}

/// Trang kiểu iOS 26: tiêu đề lớn trong nội dung, cuộn lên thì tiêu đề nhỏ hiện ở thanh trên;
/// thanh trên không có nền đặc mà là làm mờ tăng dần (progressive blur). Nút quay lại tròn kính khi có màn trước,
/// kéo xuống để tải lại (nếu có onRefresh), chừa chỗ cho thanh tab kính ở đáy.
class IosPage extends StatefulWidget {
  final String title;
  final List<Widget> slivers;
  final Widget? trailing;
  final Future<void> Function()? onRefresh;
  final Color glow;
  // Bị bắt ở lại (vd đổi mật khẩu bắt buộc) thì không hiện nút quay lại
  final bool showBack;
  final VoidCallback? onBack;
  // Phần nổi ở đáy (vd thanh nút gửi), đè lên nội dung
  final Widget? bottom;
  final bool plain;

  const IosPage({
    this.plain = false,
    super.key,
    required this.title,
    required this.slivers,
    this.trailing,
    this.onRefresh,
    this.glow = AppColors.navy,
    this.showBack = true,
    this.onBack,
    this.bottom,
  });

  @override
  State<IosPage> createState() => _IosPageState();
}

class _IosPageState extends State<IosPage> {
  static const double barHeight = 52;
  final ScrollController scroll = ScrollController();
  double offset = 0;

  @override
  void initState() {
    super.initState();
    scroll.addListener(() {
      final double value = scroll.hasClients ? scroll.offset : 0;
      // Chỉ vẽ lại khi còn trong khoảng tiêu đề đổi trạng thái
      if ((value.clamp(0, 80) - offset.clamp(0, 80)).abs() > 0.5) {
        setState(() => offset = value);
      }
    });
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double top = MediaQuery.paddingOf(context).top;
    final bool canPop = Navigator.of(context).canPop();
    final Widget? leading = widget.showBack && (canPop || widget.onBack != null)
        ? IosBackButton(onPressed: widget.onBack ?? () => Navigator.of(context).maybePop())
        : null;
    // Tiêu đề lớn cuộn khuất thì tiêu đề nhỏ hiện dần
    final double small = ((offset - 28) / 20).clamp(0.0, 1.0);
    final double blurIn = (offset / 16).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: IosColors.groupedBackground,
      body: IosBackground(
        glow: widget.glow,
        plain: widget.plain,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: CustomScrollView(
                controller: scroll,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                slivers: <Widget>[
                  SliverToBoxAdapter(child: SizedBox(height: top + barHeight)),
                  if (widget.onRefresh != null) CupertinoSliverRefreshControl(onRefresh: widget.onRefresh),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Semantics(
                        header: true,
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                            letterSpacing: -0.6,
                            height: 1.15,
                          ),
                        ),
                      ),
                    ),
                  ),
                  ...widget.slivers,
                  SliverToBoxAdapter(
                    child: SizedBox(height: MediaQuery.paddingOf(context).bottom + (widget.bottom == null ? 16 : 140)),
                  ),
                ],
              ),
            ),
            // Thanh trên: làm mờ tăng dần (hiện khi nội dung đã cuộn vào dưới thanh), nút và tiêu đề nhỏ nằm trên lớp mờ
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Opacity(
                opacity: blurIn,
                child: ProgressiveBlur(height: top + barHeight + 24),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: top,
              height: barHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: <Widget>[
                    SizedBox(width: 52, child: Align(alignment: Alignment.centerLeft, child: leading)),
                    Expanded(
                      child: Opacity(
                        opacity: small,
                        child: Text(
                          widget.title,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text),
                        ),
                      ),
                    ),
                    SizedBox(width: 52, child: Align(alignment: Alignment.centerRight, child: widget.trailing)),
                  ],
                ),
              ),
            ),
            if (widget.bottom != null) Positioned(left: 0, right: 0, bottom: 0, child: widget.bottom!),
          ],
        ),
      ),
    );
  }
}

/// Nút quay lại tròn kính có mũi tên ‹
class IosBackButton extends StatelessWidget {
  final VoidCallback? onPressed;
  // Trên bản đồ (không nằm trong thanh tiêu đề) thì cho to hơn nữa
  final double size;

  const IosBackButton({super.key, this.onPressed, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return _GlassRound(
      tooltip: t('common.back'),
      onPressed: onPressed,
      size: size,
      child: Icon(CupertinoIcons.chevron_back, size: size * 0.6, color: AppColors.navy),
    );
  }
}

/// Nút tròn kính nhỏ cho thanh trên (vd dấu +)
class IosGlassIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const IosGlassIconButton({super.key, required this.icon, required this.tooltip, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return _GlassRound(
      tooltip: tooltip,
      onPressed: onPressed,
      child: Icon(icon, size: 24, color: AppColors.navy),
    );
  }
}

class _GlassRound extends StatelessWidget {
  final String tooltip;
  final VoidCallback? onPressed;
  final Widget child;
  // 44: cỡ tối đa vừa thanh tiêu đề iOS (cũng là vùng chạm chuẩn của Apple)
  final double size;

  const _GlassRound({required this.tooltip, required this.onPressed, required this.child, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final Widget face = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: glassBlurEnabled
              ? <Color>[Colors.white.withValues(alpha: 0.6), Colors.white.withValues(alpha: 0.32)]
              : <Color>[Colors.white.withValues(alpha: 0.96), Colors.white.withValues(alpha: 0.88)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 0.8),
        boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x140C2858), blurRadius: 12, offset: Offset(0, 4))],
      ),
      alignment: Alignment.center,
      child: child,
    );
    return Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        onTap: onPressed,
        child: glassBlurEnabled
            ? ClipOval(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: face,
                ),
              )
            : face,
      ),
    );
  }
}

/// Một dòng trong IosGroup: ô biểu tượng màu, chữ chính, chữ phụ, giá trị bên phải, mũi tên ›
class IosRow extends StatelessWidget {
  final IconData? icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final bool chevron;
  final bool destructive;
  final bool centered;
  final VoidCallback? onTap;

  const IosRow({
    super.key,
    this.icon,
    this.iconColor = AppColors.navy,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.chevron = true,
    this.destructive = false,
    this.centered = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color titleColor = destructive ? IosColors.red : AppColors.text;
    final Widget titleText = Text(
      title,
      textAlign: centered ? TextAlign.center : TextAlign.start,
      style: TextStyle(fontSize: 17, color: titleColor, fontWeight: centered ? FontWeight.w500 : FontWeight.w400),
    );
    return Semantics(
      button: onTap != null,
      child: Material(
        color: Colors.white,
        child: InkWell(
          onTap: onTap,
          highlightColor: IosColors.fill,
          splashFactory: NoSplash.splashFactory,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, subtitle == null ? 10 : 9, 12, subtitle == null ? 10 : 9),
              child: Row(
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    IosIconBadge(icon: icon!, color: iconColor),
                    const SizedBox(width: 16),
                  ],
                  Expanded(
                    child: centered
                        ? titleText
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              titleText,
                              if (subtitle != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 1),
                                  child: Text(subtitle!, style: const TextStyle(fontSize: 14, color: IosColors.secondaryLabel)),
                                ),
                            ],
                          ),
                  ),
                  if (value != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(value!, style: const TextStyle(fontSize: 17, color: IosColors.secondaryLabel)),
                    ),
                  if (trailing != null) Padding(padding: const EdgeInsets.only(left: 8), child: trailing),
                  if (chevron && onTap != null && !centered)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(CupertinoIcons.chevron_forward, size: 18, color: IosColors.tertiaryLabel),
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

/// Hộp hỏi xác nhận kiểu iOS. Trả true khi bấm nút hành động.
Future<bool> showIosConfirm(
  BuildContext context, {
  required String title,
  String? message,
  required String action,
  bool destructive = true,
  String? cancel,
}) async {
  final bool? ok = await showCupertinoDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext context) => CupertinoAlertDialog(
      title: Text(title),
      content: message == null ? null : Padding(padding: const EdgeInsets.only(top: 4), child: Text(message)),
      actions: <Widget>[
        CupertinoDialogAction(onPressed: () => Navigator.of(context).pop(false), child: Text(cancel ?? t('common.cancel'))),
        CupertinoDialogAction(
          isDestructiveAction: destructive,
          isDefaultAction: !destructive,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Thông báo nổi ngắn ở đáy
void showIosToast(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(text)));
}
