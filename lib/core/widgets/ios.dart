// Khối giao diện kiểu iOS (Cupertino) cho app tài xế: nền nhóm xám nhạt có quầng màu để lớp kính
// nổi lên, nhóm ô bo góc "inset grouped" như Cài đặt của iPhone, tiêu đề nhóm chữ hoa nhỏ.
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

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

  const IosBackground({super.key, required this.child, this.glow = IosColors.red});

  @override
  Widget build(BuildContext context) {
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
            borderRadius: BorderRadius.circular(16),
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
class IosPage extends StatelessWidget {
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

  const IosPage({
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
  Widget build(BuildContext context) {
    final bool canPop = Navigator.of(context).canPop();
    final Widget? leading = showBack && (canPop || onBack != null)
        ? IosBackButton(onPressed: onBack ?? () => Navigator.of(context).maybePop())
        : null;
    return Scaffold(
      backgroundColor: IosColors.groupedBackground,
      body: IosBackground(
        glow: glow,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: CustomScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                slivers: <Widget>[
                  CupertinoSliverNavigationBar(
                    largeTitle: Text(title),
                    automaticallyImplyLeading: false,
                    automaticallyImplyTitle: false,
                    leading: leading,
                    trailing: trailing,
                    padding: const EdgeInsetsDirectional.only(start: 8, end: 8),
                    backgroundColor: IosColors.groupedBackground.withValues(alpha: 0.72),
                    border: null,
                    transitionBetweenRoutes: false,
                  ),
                  if (onRefresh != null) CupertinoSliverRefreshControl(onRefresh: onRefresh),
                  ...slivers,
                  SliverToBoxAdapter(
                    child: SizedBox(height: MediaQuery.paddingOf(context).bottom + (bottom == null ? 16 : 140)),
                  ),
                ],
              ),
            ),
            if (bottom != null) Positioned(left: 0, right: 0, bottom: 0, child: bottom!),
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
      tooltip: 'Quay lại',
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
    return Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        onTap: onPressed,
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Colors.white.withValues(alpha: 0.6), Colors.white.withValues(alpha: 0.32)],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 0.8),
                boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x140C2858), blurRadius: 12, offset: Offset(0, 4))],
              ),
              alignment: Alignment.center,
              child: child,
            ),
          ),
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

/// Hộp hỏi xác nhận kiểu iOS. Trả true khi bấm nút hành động.
Future<bool> showIosConfirm(
  BuildContext context, {
  required String title,
  String? message,
  required String action,
  bool destructive = true,
  String cancel = 'Thôi',
}) async {
  final bool? ok = await showCupertinoDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext context) => CupertinoAlertDialog(
      title: Text(title),
      content: message == null ? null : Padding(padding: const EdgeInsets.only(top: 4), child: Text(message)),
      actions: <Widget>[
        CupertinoDialogAction(onPressed: () => Navigator.of(context).pop(false), child: Text(cancel)),
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
