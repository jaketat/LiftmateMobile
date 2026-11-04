// Khối giao diện kiểu iOS (Cupertino) cho app tài xế: nền nhóm xám nhạt có quầng màu để lớp kính
// nổi lên, nhóm ô bo góc "inset grouped" như Cài đặt của iPhone, tiêu đề nhóm chữ hoa nhỏ.
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' show SpringDescription, SpringSimulation;
import 'package:flutter/services.dart' show MethodCall, MethodChannel, StandardMessageCodec;

import '../theme.dart';
import '../i18n.dart';
import 'glass.dart';

/// Màu hệ thống của iOS, theo chế độ sáng / tối (cùng giá trị với UIColor của Apple)
class IosColors {
  static Color _pick(int light, int dark) => Color(AppColors.isDark ? dark : light);

  static Color get groupedBackground => _pick(0xFFF2F2F7, 0xFF000000);
  static Color get separator => _pick(0x4D3C3C43, 0x99545458);
  static Color get secondaryLabel => _pick(0x993C3C43, 0x99EBEBF5);
  static Color get tertiaryLabel => _pick(0x4D3C3C43, 0x4DEBEBF5);
  static Color get red => _pick(0xFFFF3B30, 0xFFFF453A);
  static Color get orange => _pick(0xFFFF9500, 0xFFFF9F0A);
  static Color get green => _pick(0xFF34C759, 0xFF30D158);
  // Chế độ tối dùng cam như màu nhấn của app, không dùng xanh
  static Color get blue => _pick(0xFF007AFF, 0xFFF28C3C);
  static Color get fill => _pick(0x1F787880, 0x3D787880);
}

/// Nền xám nhóm có hai quầng màu mờ ở trên: kính trong suốt cần thứ gì phía sau mới thấy được.
class IosBackground extends StatelessWidget {
  final Widget child;
  final Color glow;
  // Nền xám trơn như Cài đặt của iPhone (không quầng màu)
  final bool plain;

  IosBackground({super.key, required this.child, Color? glow, this.plain = false}) : glow = glow ?? IosColors.red;

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
  // Biểu tượng nhỏ trước tiêu đề, giúp nhận ra nhóm nhanh hơn
  final IconData? headerIcon;
  // Nút nhỏ cuối dòng tiêu đề
  final Widget? headerTrailing;
  final String? footer;
  final Widget? footerWidget;
  final List<Widget> children;
  // Đường kẻ bắt đầu sau biểu tượng (iOS lùi đường kẻ vào bằng phần chữ)
  final double dividerIndent;

  const IosGroup({
    super.key,
    this.header,
    this.headerIcon,
    this.headerTrailing,
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
              child: Row(
                children: <Widget>[
                  if (headerIcon != null) ...<Widget>[
                    Icon(headerIcon, size: 16, color: AppColors.navy),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      header!.toUpperCase(),
                      style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel, letterSpacing: 0.2),
                    ),
                  ),
                  if (headerTrailing != null) headerTrailing!,
                ],
              ),
            ),
          ClipRRect(
            // Bo góc lớn như nhóm ô của iOS 26
            borderRadius: BorderRadius.circular(24),
            child: ColoredBox(
              color: AppColors.surface,
              child: Column(mainAxisSize: MainAxisSize.min, children: rows),
            ),
          ),
          if (footerWidget != null || footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
              child: footerWidget ??
                  Text(
                    footer!,
                    style: TextStyle(fontSize: 13, color: IosColors.secondaryLabel, height: 1.35),
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
        shape: BoxShape.circle,
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

  IosPillButton({
    super.key,
    required this.label,
    this.icon,
    Color? color,
    this.onPressed,
    this.busy = false,
  }) : color = color ?? AppColors.navy;

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
                  : <Color>[AppColors.control, AppColors.control],
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
                    // Nút hẹp hoặc chữ hệ thống cỡ lớn: rút gọn chứ không tràn
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
                      ),
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

  ProgressiveBlur({
    super.key,
    required this.height,
    this.fromTop = true,
    this.maxSigma = 14,
    Color? tint,
    this.tintOpacity = 0.75,
  }) : tint = tint ?? IosColors.groupedBackground;

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
  // Tiêu đề lớn nằm cùng hàng với nút hai bên, không xuống dòng riêng. Chỉ hợp với tiêu đề ngắn.
  final bool inlineTitle;
  // Tiêu đề riêng luôn nằm giữa hàng nút quay lại, không có tiêu đề lớn (dùng với title rỗng)
  final Widget? barTitle;
  // Trang đổi tiêu đề tại chỗ (nhiều bước trên một trang): tiêu đề mờ chuyển, không nhảy
  final bool animateTitle;

  IosPage({
    this.plain = false,
    this.inlineTitle = false,
    this.barTitle,
    this.animateTitle = false,
    super.key,
    required this.title,
    required this.slivers,
    this.trailing,
    this.onRefresh,
    Color? glow,
    this.showBack = true,
    this.onBack,
    this.bottom,
  }) : glow = glow ?? AppColors.navy;

  @override
  State<IosPage> createState() => _IosPageState();
}

/// Chuyển mờ không chồng chữ: cái cũ mờ hết trong nửa đầu, cái mới hiện trong nửa sau
Widget iosFadeThrough(Widget child, Animation<double> animation) {
  return FadeTransition(opacity: animation.drive(CurveTween(curve: const Interval(0.5, 1, curve: Curves.easeOut))), child: child);
}

class _IosPageState extends State<IosPage> {
  static const double barHeight = 52;
  static const Duration stepDuration = Duration(milliseconds: 300);
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
    // Tiêu đề cùng hàng thì khuất sớm hơn nên tiêu đề nhỏ cũng hiện sớm hơn
    final double small = ((widget.inlineTitle ? (offset - 8) / 16 : (offset - 28) / 20)).clamp(0.0, 1.0);
    final double blurIn = (offset / 16).clamp(0.0, 1.0);
    final Widget largeTitle = Text(
      widget.title,
      style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: AppColors.text, letterSpacing: -0.6, height: 1.15),
    );

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
                  SliverToBoxAdapter(child: SizedBox(height: widget.inlineTitle ? top : top + barHeight)),
                  if (widget.onRefresh != null) CupertinoSliverRefreshControl(onRefresh: widget.onRefresh),
                  if (widget.animateTitle)
                    SliverToBoxAdapter(
                      child: AnimatedSize(
                        duration: stepDuration,
                        curve: Curves.easeInOutCubic,
                        alignment: Alignment.topCenter,
                        child: AnimatedSwitcher(
                          duration: stepDuration,
                          transitionBuilder: iosFadeThrough,
                          layoutBuilder: (Widget? current, List<Widget> previous) => Stack(
                            alignment: Alignment.topLeft,
                            children: <Widget>[...previous, ?current],
                          ),
                          child: widget.title.isEmpty
                              ? const SizedBox(key: ValueKey<String>('no-title'), width: double.infinity)
                              : Padding(
                                  key: ValueKey<String>(widget.title),
                                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                                  child: Semantics(header: true, child: largeTitle),
                                ),
                        ),
                      ),
                    )
                  // Tiêu đề rỗng: trang tự có đầu trang riêng
                  else if (widget.title.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        // Cùng hàng: chừa chỗ cho nút quay lại và hai nút bên phải
                        padding: widget.inlineTitle
                            ? EdgeInsets.fromLTRB(leading == null ? 20 : 72, 0, 120, 12)
                            : const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        child: Semantics(
                          header: true,
                          child: widget.inlineTitle
                              ? SizedBox(
                                  height: barHeight,
                                  child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: largeTitle),
                                )
                              : largeTitle,
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
            // Thanh trên: nền hiện dần khi nội dung đã cuộn vào dưới thanh, đục tới hết thanh rồi tan dần để tiêu đề nhỏ không đè lên chữ.
            // Nút và tiêu đề nhỏ nằm trên lớp này
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: top + barHeight + 24,
              child: IgnorePointer(
                child: Opacity(
                  opacity: blurIn,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: <double>[0, (top + barHeight) / (top + barHeight + 24), 1],
                        colors: <Color>[
                          IosColors.groupedBackground,
                          IosColors.groupedBackground,
                          IosColors.groupedBackground.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: top,
              height: barHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: <Widget>[
                    SizedBox(width: 52, child: Align(alignment: Alignment.centerLeft, child: leading)),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: widget.animateTitle ? stepDuration : Duration.zero,
                        transitionBuilder: iosFadeThrough,
                        child: widget.barTitle != null
                            ? Semantics(key: const ValueKey<String>('bar-title'), header: true, child: Center(child: widget.barTitle))
                            : Opacity(
                                key: ValueKey<String>('small-${widget.title}'),
                                opacity: small,
                                child: Text(
                                  widget.title,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text),
                                ),
                              ),
                      ),
                    ),
                    // Rộng theo nội dung: có màn cần hai nút
                    ConstrainedBox(constraints: const BoxConstraints(minWidth: 52), child: Align(alignment: Alignment.centerRight, widthFactor: 1, child: widget.trailing)),
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
    return NativeSwap(
      native: () => NativeGlassButton(symbol: 'chevron.left', label: t('common.back'), size: size, onPressed: onPressed),
      fallback: _GlassRound(
        tooltip: t('common.back'),
        onPressed: onPressed,
        size: size,
        child: Icon(CupertinoIcons.chevron_back, size: size * 0.6, color: AppColors.navy),
      ),
    );
  }
}

/// Nút tròn kính nhỏ cho thanh trên (vd dấu +)
class IosGlassIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  // iOS: có tên SF Symbol thì dùng nút thật của hệ thống
  final String? nativeSymbol;
  // iOS: bấm là mở menu thật ngay tại nút. Nút Flutter (Android, lúc trang đang trượt) vẫn gọi [onPressed]
  final List<NativeMenuItem>? menu;
  final ValueChanged<int>? onMenu;

  const IosGlassIconButton({super.key, required this.icon, required this.tooltip, this.onPressed, this.nativeSymbol, this.menu, this.onMenu});

  @override
  Widget build(BuildContext context) {
    final Widget fallback = _GlassRound(
      tooltip: tooltip,
      onPressed: onPressed,
      child: Icon(icon, size: 24, color: AppColors.navy),
    );
    if (nativeSymbol == null) return fallback;
    return NativeSwap(
      native: () => NativeGlassButton(symbol: nativeSymbol!, label: tooltip, size: 44, foreground: AppColors.navy, onPressed: onPressed, menu: menu, onMenu: onMenu),
      fallback: fallback,
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
              : <Color>[AppColors.glass.withValues(alpha: 0.96), AppColors.glass.withValues(alpha: 0.88)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: AppColors.isDark ? 0.12 : 0.6), width: 0.8),
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
  // Thay cho ô biểu tượng khi cần vẽ riêng
  final Widget? leading;
  // Thay cho chữ tiêu đề khi cần vẽ riêng
  final Widget? titleWidget;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final bool chevron;
  final bool destructive;
  final bool centered;
  final VoidCallback? onTap;

  IosRow({
    super.key,
    this.icon,
    this.leading,
    this.titleWidget,
    Color? iconColor,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.chevron = true,
    this.destructive = false,
    this.centered = false,
    this.onTap,
  }) : iconColor = iconColor ?? AppColors.navy;

  @override
  Widget build(BuildContext context) {
    final Color titleColor = destructive ? IosColors.red : AppColors.text;
    final Widget titleText = titleWidget ??
        Text(
          title,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: TextStyle(fontSize: 17, color: titleColor, fontWeight: centered ? FontWeight.w500 : FontWeight.w400),
        );
    return Semantics(
      button: onTap != null,
      child: Material(
        color: AppColors.surface,
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
                  if (leading != null || icon != null) ...<Widget>[
                    leading ?? IosIconBadge(icon: icon!, color: iconColor),
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
                                  child: Text(subtitle!, style: TextStyle(fontSize: 14, color: IosColors.secondaryLabel)),
                                ),
                            ],
                          ),
                  ),
                  if (value != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(value!, style: TextStyle(fontSize: 17, color: IosColors.secondaryLabel)),
                    ),
                  if (trailing != null) Padding(padding: const EdgeInsets.only(left: 8), child: trailing),
                  if (chevron && onTap != null && !centered)
                    Padding(
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
  MethodChannel? channel;

  void _sync() {
    channel?.invokeMethod<void>('update', <String, Object?>{'value': widget.value, 'enabled': widget.onChanged != null});
  }

  @override
  void didUpdateWidget(covariant AdaptiveSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value || (oldWidget.onChanged == null) != (widget.onChanged == null)) _sync();
  }

  @override
  Widget build(BuildContext context) {
    final Widget flutterSwitch = CupertinoSwitch(value: widget.value, activeTrackColor: widget.activeColor, onChanged: widget.onChanged);
    if (!useNativeControls) return flutterSwitch;
    if (!nativeViewsAllowed(context)) channel = null;
    return SizedBox(
      // Giữ đúng cỡ công tắc native để hàng chứa nó không nhảy khi đổi qua lại
      width: 66,
      height: AdaptiveSwitch.nativeHeight,
      child: NativeSwap(
        native: () => UiKitView(
          viewType: 'liftmate/switch',
          creationParams: <String, Object?>{
            'value': widget.value,
            'enabled': widget.onChanged != null,
            'color': widget.activeColor.toARGB32(),
          },
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: (int id) {
            channel = MethodChannel('liftmate/switch_$id');
            channel!.setMethodCallHandler((MethodCall call) async {
              if (call.method != 'changed') return;
              final bool next = call.arguments as bool;
              widget.onChanged?.call(next);
              // Native tự gạt trước khi hỏi app. App chưa đổi giá trị (vd người dùng bấm Hủy) thì gạt về đúng trạng thái
              WidgetsBinding.instance.addPostFrameCallback((Duration _) {
                if (mounted && widget.value != next) _sync();
              });
            });
          },
        ),
        fallback: Center(child: flutterSwitch),
      ),
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
  static Color get secondaryFill => AppColors.isDark ? const Color(0x33FFFFFF) : const Color(0x1F3C3C43);
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
                          filter: glassBackdropFilter(glassBlur * shown, _saturation(1 + (glassSaturation - 1) * shown)),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppColors.glass.withValues(alpha: glassFillOpacity * shown),
                              borderRadius: radius,
                              border: Border.all(color: Colors.white.withValues(alpha: (AppColors.isDark ? 0.15 : 0.7) * shown), width: 1),
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
                                style: TextStyle(fontSize: 15, height: 1.35, color: AppColors.text),
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

/// Phản hồi khi chạm vào khối kính lớn như sheet: vệt sáng nhẹ đi theo ngón tay, khối nảy lên.
/// Ngón tay bắt đầu kéo thì thôi nảy, để kéo sheet và cuộn danh sách không bị phóng to theo.
class GlassTouchFeedback extends StatefulWidget {
  // Nhỏ hơn IosPressBounce vì khối to: cùng tỉ lệ thì mép sheet dịch quá xa
  static const double pressedScale = 1.012;
  static const double glowRadius = 120;
  static const double dragSlop = 10;

  final BorderRadius borderRadius;
  final Widget child;

  const GlassTouchFeedback({super.key, required this.borderRadius, required this.child});

  @override
  State<GlassTouchFeedback> createState() => _GlassTouchFeedbackState();
}

class _GlassTouchFeedbackState extends State<GlassTouchFeedback> with TickerProviderStateMixin {
  late final AnimationController scale = AnimationController.unbounded(vsync: this, value: 1);
  late final AnimationController glow = AnimationController(vsync: this);
  final ValueNotifier<Offset> finger = ValueNotifier<Offset>(Offset.zero);
  Offset pressedAt = Offset.zero;
  int pointers = 0;

  void _springTo(double target) {
    scale.animateWith(SpringSimulation(IosPressBounce.spring, scale.value, target, scale.velocity));
  }

  void _down(PointerDownEvent event) {
    pointers++;
    if (pointers != 1) return;
    pressedAt = event.localPosition;
    finger.value = event.localPosition;
    _springTo(GlassTouchFeedback.pressedScale);
    glow.animateTo(1, duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
  }

  void _move(PointerMoveEvent event) {
    finger.value = event.localPosition;
    if ((event.localPosition - pressedAt).distance > GlassTouchFeedback.dragSlop && scale.value != 1) _springTo(1);
  }

  void _release(PointerEvent event) {
    pointers--;
    if (pointers != 0) return;
    _springTo(1);
    glow.animateTo(0, duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
  }

  @override
  void dispose() {
    scale.dispose();
    glow.dispose();
    finger.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Android: phóng to cả khối buộc GPU tầm trung vẽ lại toàn bộ nội dung bên trong, không đáng với một hiệu ứng nhỏ
    if (!useNativeControls) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _release,
      onPointerCancel: _release,
      child: ScaleTransition(
        scale: scale,
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: <Widget>[
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: widget.borderRadius,
                  child: CustomPaint(
                    painter: _TouchGlowPainter(
                      glow: glow,
                      finger: finger,
                      // Nền sáng cần vệt đậm hơn mới thấy được trên kính
                      color: Colors.white.withValues(alpha: AppColors.isDark ? 0.2 : 0.65),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TouchGlowPainter extends CustomPainter {
  final Animation<double> glow;
  final ValueListenable<Offset> finger;
  final Color color;

  _TouchGlowPainter({required this.glow, required this.finger, required this.color}) : super(repaint: Listenable.merge(<Listenable>[glow, finger]));

  @override
  void paint(Canvas canvas, Size size) {
    if (glow.value == 0) return;
    final Rect circle = Rect.fromCircle(center: finger.value, radius: GlassTouchFeedback.glowRadius);
    canvas.drawCircle(
      finger.value,
      GlassTouchFeedback.glowRadius,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[color.withValues(alpha: color.a * glow.value), color.withValues(alpha: 0)],
        ).createShader(circle),
    );
  }

  @override
  bool shouldRepaint(_TouchGlowPainter oldDelegate) => oldDelegate.color != color;
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

// Hộp thoại và menu chọn thật của iOS, phần native nằm trong ios/Runner/AppDelegate.swift
const MethodChannel _nativeDialogs = MethodChannel('liftmate/native_dialogs');

/// Một lựa chọn trong [showIosActionSheet]
class IosSheetOption<T> {
  final T value;
  final String label;
  final bool destructive;

  const IosSheetOption(this.value, this.label, {this.destructive = false});
}

/// Khung của nút nguồn trên màn hình, để menu bật ra từ đúng nút đó
Rect? _anchorRect(BuildContext? anchor) {
  final RenderObject? box = anchor?.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Menu chọn từ đáy màn hình, có nút Hủy. Trả giá trị đã chọn, null khi hủy.
/// [anchor]: context của nút mở menu thì menu bật ra từ nút đó, chạm ra ngoài là hủy.
/// iOS: UIAlertController thật (iOS dưới 26 trên iPhone luôn hiện từ đáy). Android: CupertinoActionSheet, có nút nguồn thì menu thả xuống.
Future<T?> showIosActionSheet<T>(
  BuildContext context, {
  String? title,
  String? message,
  BuildContext? anchor,
  required List<IosSheetOption<T>> options,
}) async {
  final Rect? anchorRect = _anchorRect(anchor);
  if (useNativeControls) {
    final int? index = await _nativeDialogs.invokeMethod<int>('sheet', <String, Object?>{
      'title': title,
      'message': message,
      if (anchorRect != null)
        'anchor': <String, double>{'x': anchorRect.left, 'y': anchorRect.top, 'width': anchorRect.width, 'height': anchorRect.height},
      'actions': <Map<String, String>>[
        for (final IosSheetOption<T> option in options)
          <String, String>{'label': option.label, 'style': option.destructive ? 'destructive' : 'default'},
        <String, String>{'label': t('common.cancel'), 'style': 'cancel'},
      ],
    });
    return index == null ? null : options[index].value;
  }
  if (anchorRect != null) {
    final Size screen = MediaQuery.sizeOf(context);
    return showMenu<T>(
      context: context,
      position: RelativeRect.fromLTRB(anchorRect.left, anchorRect.bottom + 6, screen.width - anchorRect.right, screen.height - anchorRect.bottom),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      items: <PopupMenuEntry<T>>[
        for (final IosSheetOption<T> option in options)
          PopupMenuItem<T>(
            value: option.value,
            child: Text(option.label, style: TextStyle(fontSize: 16, color: option.destructive ? IosColors.red : AppColors.text)),
          ),
      ],
    );
  }
  return showCupertinoModalPopup<T>(
    context: context,
    builder: (BuildContext context) => CupertinoActionSheet(
      title: title == null ? null : Text(title),
      message: message == null ? null : Text(message),
      actions: <Widget>[
        for (final IosSheetOption<T> option in options)
          CupertinoActionSheetAction(
            isDestructiveAction: option.destructive,
            onPressed: () => Navigator.of(context).pop(option.value),
            child: Text(option.label, maxLines: 2, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17)),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        isDefaultAction: true,
        onPressed: () => Navigator.of(context).pop(),
        child: Text(t('common.cancel')),
      ),
    ),
  );
}

/// Hộp hỏi xác nhận. Trả true khi bấm nút hành động. iOS: UIAlertController thật.
/// Android: hành động nguy hiểm thì nút Hủy là nút nổi bật, nút hành động nền xám chữ đỏ, để khó bấm nhầm.
Future<bool> showIosConfirm(
  BuildContext context, {
  required String title,
  String? message,
  required String action,
  bool destructive = true,
  String? cancel,
}) async {
  if (useNativeControls) {
    final int? index = await _nativeDialogs.invokeMethod<int>('alert', <String, Object?>{
      'title': title,
      'message': message,
      'actions': <Map<String, String>>[
        <String, String>{'label': cancel ?? t('common.cancel'), 'style': 'cancel'},
        <String, String>{'label': action, 'style': destructive ? 'destructive' : 'default'},
      ],
    });
    return index == 1;
  }
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

OverlayEntry? _currentToast;

/// Thông báo ngắn kiểu iOS: viên nổi ở trên cùng, tự ẩn, chạm hoặc vuốt lên để ẩn sớm. Thông báo mới thay thông báo đang hiện.
/// Nằm ở lớp trên cùng của app nên vẫn còn khi màn vừa gọi đã đóng.
void showIosToast(BuildContext context, String text, {bool isError = false}) {
  if (!context.mounted) return;
  final OverlayState overlay = Overlay.of(context, rootOverlay: true);
  _currentToast?.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (BuildContext context) => _IosToast(
      text: text,
      isError: isError,
      onDone: () {
        if (identical(_currentToast, entry)) _currentToast = null;
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _currentToast = entry;
  overlay.insert(entry);
}

class _IosToast extends StatefulWidget {
  final String text;
  final bool isError;
  final VoidCallback onDone;

  const _IosToast({required this.text, required this.isError, required this.onDone});

  @override
  State<_IosToast> createState() => _IosToastState();
}

class _IosToastState extends State<_IosToast> with TickerProviderStateMixin {
  // 0 là khuất phía trên, 1 là đúng chỗ. Spring vượt qua 1 một chút rồi về, như thông báo của iOS
  late final AnimationController slide = AnimationController.unbounded(vsync: this, value: 0);
  // Đếm giờ hiển thị bằng đồng hồ animation
  late final AnimationController life = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  bool leaving = false;

  @override
  void initState() {
    super.initState();
    slide.animateWith(SpringSimulation(const SpringDescription(mass: 1, stiffness: 260, damping: 22), 0, 1, 0));
    life.forward().whenComplete(leave);
  }

  void leave() {
    if (leaving || !mounted) return;
    leaving = true;
    slide.animateTo(0, duration: const Duration(milliseconds: 220), curve: Curves.easeIn).whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    slide.dispose();
    life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double top = MediaQuery.paddingOf(context).top + 8;
    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: Center(
        child: AnimatedBuilder(
          animation: slide,
          builder: (BuildContext context, Widget? pill) {
            return Transform.translate(
              offset: Offset(0, (slide.value - 1) * (top + 80)),
              child: Opacity(opacity: slide.value.clamp(0.0, 1.0), child: pill),
            );
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: leave,
            onVerticalDragEnd: (DragEndDetails details) {
              if ((details.primaryVelocity ?? 0) < 0) leave();
            },
            child: Semantics(
              liveRegion: true,
              child: Glass(
                borderRadius: BorderRadius.circular(26),
                opacity: 0.9,
                padding: const EdgeInsets.fromLTRB(14, 12, 18, 12),
                child: Material(
                  type: MaterialType.transparency,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        widget.isError ? CupertinoIcons.exclamationmark_circle_fill : CupertinoIcons.checkmark_circle_fill,
                        size: 22,
                        color: widget.isError ? IosColors.red : IosColors.green,
                      ),
                      const SizedBox(width: 9),
                      Flexible(
                        child: Text(
                          widget.text,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.25),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Nút lọc dạng viên thuốc trong hàng cuộn ngang (Đơn hàng, Đội xe, Bảo trì)
class IosFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const IosFilterChip({super.key, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: IosPressBounce(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? AppColors.navy : AppColors.raised,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: selected ? Colors.white : AppColors.text),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hàng nút lọc cuộn ngang. Khóa null = "Tất cả".
class IosFilterBar<T> extends StatelessWidget {
  final Map<T?, String> options;
  final T? selected;
  final ValueChanged<T?> onSelected;

  const IosFilterBar({super.key, required this.options, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: <Widget>[
          for (final MapEntry<T?, String> option in options.entries)
            IosFilterChip(label: option.value, selected: option.key == selected, onTap: () => onSelected(option.key)),
        ],
      ),
    );
  }
}

/// Thẻ nổi bo góc lớn trong danh sách (một đơn, một xe, một lịch), bấm thì mờ nhẹ
class IosCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  // Viền màu khi cần gây chú ý (vd lịch quá hạn)
  final Color? borderColor;

  const IosCard({super.key, required this.child, this.onTap, this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        pressedOpacity: 0.7,
        onPressed: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.raised,
            borderRadius: BorderRadius.circular(22),
            border: borderColor == null ? null : Border.all(color: borderColor!, width: 1.5),
            boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x0F0C2858), blurRadius: 14, offset: Offset(0, 4))],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Dòng "nhãn ..... giá trị" trong nhóm, như ô thông tin của Cài đặt. Giá trị dài thì xuống dòng, không tràn.
class IosValueRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final VoidCallback? onTap;

  const IosValueRow({super.key, required this.label, required this.value, this.valueColor, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onTap,
        highlightColor: IosColors.fill,
        splashFactory: NoSplash.splashFactory,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: TextStyle(fontSize: 16, color: AppColors.text)),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    value,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 16, color: valueColor ?? IosColors.secondaryLabel),
                  ),
                ),
                if (onTap != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6, top: 1),
                    child: Icon(CupertinoIcons.chevron_forward, size: 18, color: IosColors.tertiaryLabel),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Chữ giữa màn khi danh sách trống hoặc lỗi, kèm nút (vd Thử lại)
class IosCenterMessage extends StatelessWidget {
  final String text;
  final IconData icon;
  final String? action;
  final VoidCallback? onAction;

  const IosCenterMessage({super.key, required this.text, this.icon = CupertinoIcons.doc_text, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 44, color: IosColors.tertiaryLabel),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: IosColors.secondaryLabel, height: 1.35)),
          if (action != null) CupertinoButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

/// Một ô nhập trong nhóm: nhãn bên trái, chữ nhập canh phải như ô Giá báo của màn tạo đơn
class IosFieldRow extends StatelessWidget {
  final String label;
  // Dòng nhỏ dưới nhãn, vd "không bắt buộc"
  final String? hint;
  final TextEditingController controller;
  final String placeholder;
  final bool enabled;
  final TextInputType keyboardType;
  // Ô bắt buộc cần gây chú ý: chữ đỏ
  final bool highlight;
  final ValueChanged<String>? onChanged;

  const IosFieldRow({
    super.key,
    required this.label,
    this.hint,
    required this.controller,
    required this.placeholder,
    this.enabled = true,
    this.keyboardType = TextInputType.text,
    this.highlight = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(label, style: TextStyle(fontSize: 16, color: AppColors.text)),
                if (hint != null)
                  Text(hint!, style: TextStyle(fontSize: 13, color: highlight ? AppColors.errorText : IosColors.secondaryLabel)),
              ],
            ),
          ),
          Expanded(
            child: CupertinoTextField(
              controller: controller,
              enabled: enabled,
              textAlign: TextAlign.right,
              keyboardType: keyboardType,
              placeholder: placeholder,
              placeholderStyle: TextStyle(fontSize: 16, color: highlight ? AppColors.errorText.withValues(alpha: 0.5) : IosColors.tertiaryLabel),
              style: TextStyle(fontSize: 16, color: highlight ? AppColors.errorText : AppColors.text),
              decoration: null,
              padding: const EdgeInsets.symmetric(vertical: 12),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ô nhập nhiều dòng chiếm cả hàng trong nhóm (mô tả, ghi chú, lý do)
class IosTextArea extends StatelessWidget {
  final TextEditingController controller;
  final String placeholder;
  final bool enabled;
  final int minLines;
  final int maxLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;

  const IosTextArea({
    super.key,
    required this.controller,
    required this.placeholder,
    this.enabled = true,
    this.minLines = 2,
    this.maxLines = 5,
    this.maxLength,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoTextField(
      controller: controller,
      enabled: enabled,
      placeholder: placeholder,
      placeholderStyle: TextStyle(fontSize: 16, color: IosColors.tertiaryLabel),
      style: TextStyle(fontSize: 16, height: 1.35, color: AppColors.text),
      decoration: null,
      padding: const EdgeInsets.all(16),
      minLines: minLines,
      maxLines: maxLines,
      maxLength: maxLength,
      onChanged: onChanged,
    );
  }
}

/// Câu lỗi chữ đỏ nằm giữa các nhóm, ngay trên nút lưu
class IosErrorText extends StatelessWidget {
  final String text;

  const IosErrorText(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 14),
      child: Text(text, style: TextStyle(fontSize: 14, height: 1.35, color: AppColors.errorText)),
    );
  }
}

/// Nút chính dạng viên ở cuối form, cách lề như nhóm ô
class IosFormButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool busy;
  final VoidCallback? onPressed;

  const IosFormButton({super.key, required this.label, this.icon, this.busy = false, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: IosPillButton(label: label, icon: icon, busy: busy, onPressed: onPressed),
    );
  }
}

/// Ô nhập dùng trong hộp thoại iOS: nền trắng bo tròn trên lớp kính
class IosDialogField extends StatelessWidget {
  final TextEditingController controller;
  final String placeholder;
  final TextInputType keyboardType;
  final int maxLines;
  final int? maxLength;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  const IosDialogField({
    super.key,
    required this.controller,
    required this.placeholder,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
    this.maxLength,
    this.autofocus = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoTextField(
      controller: controller,
      autofocus: autofocus,
      placeholder: placeholder,
      keyboardType: keyboardType,
      minLines: 1,
      maxLines: maxLines,
      maxLength: maxLength,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
      onChanged: onChanged,
    );
  }
}
