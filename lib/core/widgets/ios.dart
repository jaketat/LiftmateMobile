// Khối giao diện kiểu iOS (Cupertino) cho app tài xế: nền nhóm xám nhạt có quầng màu để lớp kính
// nổi lên, nhóm ô bo góc "inset grouped" như Cài đặt của iPhone, tiêu đề nhóm chữ hoa nhỏ.
import 'dart:ui' show ImageFilter;

import 'package:cupertino_native/cupertino_native.dart' show CNSwitch, CNSwitchController;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' show SpringDescription, SpringSimulation;

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
            : CustomPaint(
                foregroundPainter: GlassRimPainter(BorderRadius.circular(size / 2)),
                child: face,
              ),
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

/// Công tắc: iOS dùng UISwitch native, nền tảng khác dùng CupertinoSwitch. onChanged null: bị khóa.
class AdaptiveSwitch extends StatefulWidget {
  // UISwitch của iOS 26 rộng 63: chiều cao này cho khung đủ rộng, không cắt mất công tắc
  static const double nativeHeight = 40;

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color activeColor;

  const AdaptiveSwitch({super.key, required this.value, required this.onChanged, required this.activeColor});

  @override
  State<AdaptiveSwitch> createState() => _AdaptiveSwitchState();
}

class _AdaptiveSwitchState extends State<AdaptiveSwitch> {
  final CNSwitchController controller = CNSwitchController();

  void _changed(bool next) {
    widget.onChanged?.call(next);
    // Native tự gạt trước khi hỏi app. Nếu app chưa đổi giá trị (vd người dùng bấm Hủy) thì gạt về đúng trạng thái
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted && widget.value != next) controller.setValue(widget.value, animated: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!useNativeControls) {
      return CupertinoSwitch(value: widget.value, activeTrackColor: widget.activeColor, onChanged: widget.onChanged);
    }
    return CNSwitch(
      value: widget.value,
      enabled: widget.onChanged != null,
      color: widget.activeColor,
      height: AdaptiveSwitch.nativeHeight,
      controller: controller,
      onChanged: _changed,
    );
  }
}

enum IosDialogActionStyle { primary, secondary, destructive }

class IosDialogAction {
  final String label;
  final IosDialogActionStyle style;
  // null: nút bị khóa
  final VoidCallback? onPressed;

  const IosDialogAction({required this.label, required this.style, required this.onPressed});
}

/// Hộp thoại kiểu iOS 26: góc bo lớn, viền sáng, chữ căn trái, nút dạng viên thuốc.
/// Hai nút vừa một hàng thì xếp ngang, nhãn dài thì xếp dọc với nút cuối danh sách (nút chính) lên trên.
class IosDialog extends StatelessWidget {
  static const double maxWidth = 340;
  static const double buttonHeight = 50;
  static const double buttonGap = 10;
  static const double buttonInset = 14;
  static const BorderRadius radius = BorderRadius.all(Radius.circular(36));
  static const TextStyle buttonText = TextStyle(fontSize: 17, fontWeight: FontWeight.w600);
  // Nút phụ cũng trong nhẹ, thấy được nền kính phía sau
  static const Color secondaryFill = Color(0x1F3C3C43);
  // Kính kiểu iOS: nền sau được làm mờ và tăng độ rực, rồi phủ lớp trắng khá dày, nên hộp sáng mà vẫn thấy màu phía sau.
  // Là các số ước lượng theo mắt, đổi ở đây nếu thấy đục, tối hay khó đọc.
  static const double glassFillOpacity = 0.68;
  static const double glassBlur = 18;
  static const double glassSaturation = 1.8;

  static ColorFilter _saturation(double s) {
    // Ma trận bão hòa màu theo trọng số độ sáng Rec. 709
    const double r = 0.2126, g = 0.7152, b = 0.0722;
    final double i = 1 - s;
    return ColorFilter.matrix(<double>[
      i * r + s, i * g, i * b, 0, 0,
      i * r, i * g + s, i * b, 0, 0,
      i * r, i * g, i * b + s, 0, 0,
      0, 0, 0, 1, 0,
    ]);
  }

  final String title;
  final String? message;
  final Widget? content;
  final List<IosDialogAction> actions;

  const IosDialog({super.key, required this.title, this.message, this.content, required this.actions});

  bool _fitsInRow(BuildContext context, double width) {
    if (actions.length != 2) return false;
    final double available = (width - buttonGap) / 2 - 24;
    for (final IosDialogAction action in actions) {
      final TextPainter painter = TextPainter(
        text: TextSpan(text: action.label, style: DefaultTextStyle.of(context).style.merge(buttonText)),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final double needed = painter.width;
      painter.dispose();
      if (needed > available) return false;
    }
    return true;
  }

  Widget _button(IosDialogAction action) {
    final (Color background, Color foreground) = switch (action.style) {
      IosDialogActionStyle.primary => (AppColors.navy, Colors.white),
      IosDialogActionStyle.secondary => (secondaryFill, AppColors.text),
      IosDialogActionStyle.destructive => (secondaryFill, IosColors.red),
    };
    return Semantics(
      button: true,
      enabled: action.onPressed != null,
      excludeSemantics: true,
      label: action.label,
      onTap: action.onPressed,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: const Size(44, buttonHeight),
        color: background,
        disabledColor: background.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        onPressed: action.onPressed,
        child: Text(
          action.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: buttonText.copyWith(color: action.onPressed == null ? foreground.withValues(alpha: 0.4) : foreground),
        ),
      ),
    );
  }

  Widget _buttons(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (_fitsInRow(context, constraints.maxWidth)) {
          return Row(
            children: <Widget>[
              Expanded(child: _button(actions[0])),
              const SizedBox(width: buttonGap),
              Expanded(child: _button(actions[1])),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final IosDialogAction action in actions.reversed) ...<Widget>[
              _button(action),
              if (action != actions.first) const SizedBox(height: buttonGap),
            ],
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? body = message;
    final Widget? extra = content;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxWidth),
          child: Semantics(
            scopesRoute: true,
            explicitChildNodes: true,
            namesRoute: true,
            label: title,
            child: DefaultTextStyle(
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: AppColors.text, decoration: TextDecoration.none),
              // Kính mờ trong nhẹ như iOS 26. Hộp chỉ hiện ngắn, đứng yên nên được làm mờ cả trên Android.
              // Không được bọc lớp kính trong FadeTransition hay Opacity: lớp làm mờ nằm trong lớp độ trong suốt thì không
              // lấy được nền phía sau, hộp sẽ trong suốt suốt lúc mở rồi đột ngột đục lên. Nên tăng dần độ mờ và độ đục của kính.
              child: AnimatedBuilder(
                animation: ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation,
                builder: (BuildContext context, Widget? column) {
                  final double shown = Curves.easeOutCubic.transform((ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation).value);
                  return Transform.scale(
                    scale: 0.94 + 0.06 * shown,
                    child: IosPressBounce(child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        boxShadow: <BoxShadow>[
                          BoxShadow(color: const Color(0x22000000).withValues(alpha: 0.133 * shown), blurRadius: 40, offset: const Offset(0, 14)),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: radius,
                        child: BackdropFilter(
                          filter: ImageFilter.compose(
                            outer: _saturation(1 + (glassSaturation - 1) * shown),
                            inner: ImageFilter.blur(sigmaX: glassBlur * shown, sigmaY: glassBlur * shown),
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: glassFillOpacity * shown),
                              borderRadius: radius,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.7 * shown), width: 1),
                            ),
                            // Chữ và nút nằm trên kính nên mờ dần được, không ảnh hưởng lớp làm mờ
                            child: Opacity(opacity: shown, child: column),
                          ),
                        ),
                      ),
                    )),
                  );
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              title,
                              textAlign: TextAlign.start,
                              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.25),
                            ),
                            if (body != null) ...<Widget>[
                              const SizedBox(height: 8),
                              Text(
                                body,
                                textAlign: TextAlign.start,
                                // Gần đen để vẫn đọc rõ khi kính trong và nền phía sau tối
                                style: const TextStyle(fontSize: 15, height: 1.35, color: Color(0xFF2C2C2E)),
                              ),
                            ],
                            if (extra != null) ...<Widget>[const SizedBox(height: 12), extra],
                          ],
                        ),
                      ),
                    ),
                    Padding(padding: const EdgeInsets.fromLTRB(buttonInset, 16, buttonInset, buttonInset), child: _buttons(context)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Phóng nhẹ khi ngón tay chạm xuống, buông ra thì nảy về theo lò xo như kính iOS 26.
/// Chỉ lắng nghe chạm chứ không giữ, nên nút và cuộn bên trong vẫn hoạt động bình thường.
class IosPressBounce extends StatefulWidget {
  static const double pressedScale = 1.035;
  // Tắt dần chưa tới hạn nên vượt quá một chút rồi mới về đúng cỡ. Là số ước lượng theo mắt.
  static const SpringDescription spring = SpringDescription(mass: 1, stiffness: 420, damping: 18);

  final Widget child;

  const IosPressBounce({super.key, required this.child});

  @override
  State<IosPressBounce> createState() => _IosPressBounceState();
}

class _IosPressBounceState extends State<IosPressBounce> with SingleTickerProviderStateMixin {
  late final AnimationController scale = AnimationController.unbounded(vsync: this, value: 1);
  int pointers = 0;

  void _springTo(double target) {
    scale.animateWith(SpringSimulation(IosPressBounce.spring, scale.value, target, scale.velocity));
  }

  void _release(PointerEvent event) {
    pointers--;
    if (pointers == 0) _springTo(1);
  }

  @override
  void dispose() {
    scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (PointerDownEvent event) {
        pointers++;
        if (pointers == 1) _springTo(IosPressBounce.pressedScale);
      },
      onPointerUp: _release,
      onPointerCancel: _release,
      child: ScaleTransition(scale: scale, child: widget.child),
    );
  }
}

/// Mở [IosDialog]. Route không tự fade như showCupertinoDialog, vì fade làm hỏng lớp kính (xem IosDialog.build).
Future<T?> showIosDialog<T>(BuildContext context, {required WidgetBuilder builder, bool barrierDismissible = true}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    // Nền chỉ tối rất nhẹ: kính trong nên nền tối sẽ làm cả hộp xỉn đi
    barrierColor: const Color(0x14000000),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (BuildContext context, Animation<double> animation, Animation<double> secondary) => builder(context),
    transitionBuilder: (BuildContext context, Animation<double> animation, Animation<double> secondary, Widget child) => child,
  );}

/// Hộp hỏi xác nhận kiểu iOS 26. Trả true khi bấm nút hành động.
/// Hành động nguy hiểm thì nút Hủy là nút nổi bật, nút hành động nền xám chữ đỏ, để khó bấm nhầm.
Future<bool> showIosConfirm(
  BuildContext context, {
  required String title,
  String? message,
  required String action,
  bool destructive = true,
  String? cancel,
}) async {
  final bool? ok = await showIosDialog<bool>(
    context,
    builder: (BuildContext context) => IosDialog(
      title: title,
      message: message,
      actions: <IosDialogAction>[
        IosDialogAction(
          label: cancel ?? t('common.cancel'),
          style: destructive ? IosDialogActionStyle.primary : IosDialogActionStyle.secondary,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        IosDialogAction(
          label: action,
          style: destructive ? IosDialogActionStyle.destructive : IosDialogActionStyle.primary,
          onPressed: () => Navigator.of(context).pop(true),
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
