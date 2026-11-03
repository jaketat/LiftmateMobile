// Màn đổi mật khẩu (N5, doc mục 3.5), kiểu sheet của iOS. Hai cách vào:
// 1. Bị bắt đổi (mustChangePassword = true): bảo vệ ở router nhốt ở đây, phủ kín màn, có câu giải thích + nút Đăng xuất, không có nút đóng.
// 2. Tự đổi (bấm từ menu): sheet trượt từ dưới lên, có nút đóng, đổi xong thì quay về màn trước.
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState, ref
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.canPop, context.pop, context.go
import 'package:go_router/go_router.dart';

import '../../core/api/call.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/ios.dart';
import 'session_provider.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() {
    return _ChangePasswordScreenState();
  }
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final TextEditingController currentController = TextEditingController();
  final TextEditingController newController = TextEditingController();
  final TextEditingController confirmController = TextEditingController();
  bool isSubmitting = false;
  // Lỗi chung, hiện trên nút (vd mất mạng)
  String? errorText;
  // Lỗi từng ô, khóa là tên trường server trả về: currentPassword, newPassword, confirmPassword
  Map<String, String> fieldErrors = <String, String>{};

  @override
  void dispose() {
    currentController.dispose();
    newController.dispose();
    confirmController.dispose();
    super.dispose();
  }

  // Gõ lại vào ô nào thì xóa lỗi của ô đó
  void clearFieldError(String field) {
    // Luôn vẽ lại: nút "Đổi mật khẩu" chỉ sáng khi đủ cả 3 ô
    setState(() {
      fieldErrors.remove(field);
    });
  }

  Future<void> submit() async {
    setState(() {
      isSubmitting = true;
      errorText = null;
      fieldErrors = <String, String>{};
    });

    try {
      await ref.read(sessionProvider.notifier).updatePassword(
            currentController.text,
            newController.text,
            confirmController.text,
          );
      if (!mounted) {
        return;
      }
      showIosToast(context, t('password.changed'));
      // Tự đổi (có màn trước) thì quay lại. Bị bắt đổi (không có màn trước) thì vào màn chính.
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        isSubmitting = false;
        fieldErrors = Map<String, String>.from(error.fieldErrors);
        // Sai mật khẩu hiện tại: server không gắn vào ô nào, mình tự gắn vào ô đầu
        if (error.code == 'INVALID_CURRENT_PASSWORD') {
          fieldErrors['currentPassword'] = error.message;
        }
        // Không có lỗi ô nào thì hiện câu lỗi chung
        if (fieldErrors.isEmpty) {
          errorText = error.message;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        isSubmitting = false;
        errorText = errorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Chỉ cần biết có đang bị bắt đổi không, nên chỉ nhìn 1 lần lúc vẽ
    final Session? session = ref.watch(sessionProvider).value;
    final bool isForced = session != null && session.mustChangePassword;

    final bool ready = currentController.text.isNotEmpty &&
        newController.text.isNotEmpty &&
        confirmController.text.isNotEmpty;
    final String? newError = fieldErrors['newPassword'] ?? fieldErrors['confirmPassword'];

    final Widget form = ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(_sideInset, isForced ? MediaQuery.paddingOf(context).top + 32 : 72, _sideInset, MediaQuery.paddingOf(context).bottom + 24),
      children: <Widget>[
        const Center(child: _KeyBadge()),
        const SizedBox(height: 36),
        Text(
          t('password.title'),
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text, letterSpacing: -0.3),
        ),
        // Bị bắt đổi: nói rõ vì sao phải đổi
        if (isForced) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            t('password.temporaryNotice'),
            style: TextStyle(fontSize: 15, color: IosColors.secondaryLabel, height: 1.35),
          ),
        ],
        const SizedBox(height: 20),
        _FieldGroup(
          children: <Widget>[
            PasswordField(
              placeholder: isForced ? t('password.temporary') : t('password.current'),
              controller: currentController,
              hasError: fieldErrors['currentPassword'] != null,
              onChanged: () => clearFieldError('currentPassword'),
            ),
          ],
        ),
        _Footnote(text: fieldErrors['currentPassword'], isError: true),
        const SizedBox(height: 14),
        _FieldGroup(
          children: <Widget>[
            PasswordField(
              placeholder: t('password.newPlaceholder'),
              controller: newController,
              hasError: fieldErrors['newPassword'] != null,
              onChanged: () => clearFieldError('newPassword'),
            ),
            PasswordField(
              placeholder: t('password.confirmPlaceholder'),
              controller: confirmController,
              hasError: fieldErrors['confirmPassword'] != null,
              onChanged: () => clearFieldError('confirmPassword'),
            ),
          ],
        ),
        // Lỗi của ô thì ghi đỏ dưới nhóm, không lỗi thì ghi chú
        _Footnote(text: newError ?? t('password.signOutOthers'), isError: newError != null),
        const SizedBox(height: 28),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(errorText!, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: IosColors.red)),
          ),
        _CapsuleButton(
          label: t('password.title'),
          busy: isSubmitting,
          onPressed: ready ? submit : null,
        ),
        // Bị bắt đổi mà không muốn đổi lúc này thì vẫn phải thoát ra được
        if (isForced) ...<Widget>[
          const SizedBox(height: 8),
          CupertinoButton(
            onPressed: isSubmitting ? null : () => ref.read(sessionProvider.notifier).signOut(),
            child: Text(t('common.signOut'), style: TextStyle(fontSize: 17, color: IosColors.red)),
          ),
        ],
      ],
    );

    // Bị bắt đổi thì không có màn nào phía sau: phủ kín màn hình, không có nút đóng
    if (isForced) {
      return Scaffold(backgroundColor: AppColors.surface, body: form);
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 8),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(_sheetRadius)),
          child: ColoredBox(
            color: AppColors.surface,
            child: Stack(
              children: <Widget>[
                // Khung Scaffold đã chừa phần trên, không chừa thêm lần nữa
                MediaQuery.removePadding(context: context, removeTop: true, child: form),
                Positioned(
                  top: 16,
                  right: 16,
                  child: nativeViewsAllowed(context)
                      ? NativeGlassButton(
                          symbol: 'xmark',
                          label: t('common.close'),
                          size: 44,
                          foreground: AppColors.text,
                          onPressed: () => context.pop(),
                        )
                      : IosGlassIconButton(
                          icon: CupertinoIcons.xmark,
                          tooltip: t('common.close'),
                          onPressed: () => context.pop(),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const double _sheetRadius = 32;
const double _sideInset = 28;

/// Biểu tượng chìa khóa trong vòng tròn ở đầu màn
class _KeyBadge extends StatelessWidget {
  const _KeyBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: IosColors.blue, width: 4)),
      alignment: Alignment.center,
      // Biểu tượng nằm ngang, xoay cho đầu chìa khóa lên trên
      child: Transform.rotate(
        angle: math.pi / 2,
        child: Icon(Icons.key_rounded, size: 44, color: IosColors.blue),
      ),
    );
  }
}

/// Nhóm ô nhập nền xám bo tròn, có đường kẻ mảnh giữa các ô
class _FieldGroup extends StatelessWidget {
  final List<Widget> children;

  const _FieldGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: ColoredBox(
        color: AppColors.fillSoft,
        child: Column(
          children: <Widget>[
            for (int index = 0; index < children.length; index++) ...<Widget>[
              if (index > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Divider(height: 1, thickness: 0.5, color: IosColors.separator),
                ),
              children[index],
            ],
          ],
        ),
      ),
    );
  }
}

/// Dòng chữ nhỏ dưới nhóm ô nhập: ghi chú hoặc lỗi. Không có chữ thì không chiếm chỗ
class _Footnote extends StatelessWidget {
  final String? text;
  final bool isError;

  const _Footnote({required this.text, required this.isError});

  @override
  Widget build(BuildContext context) {
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Text(
        text!,
        style: TextStyle(fontSize: 13, color: isError ? IosColors.red : IosColors.secondaryLabel, height: 1.35),
      ),
    );
  }
}

/// Nút chính hình viên thuốc có viền kính. Chưa bấm được thì xám, chữ nhạt
class _CapsuleButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  const _CapsuleButton({required this.label, required this.busy, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null && !busy;
    final BorderRadius radius = BorderRadius.circular(999);
    return Semantics(
      button: true,
      enabled: enabled,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: enabled ? onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 52,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: radius,
            color: enabled || busy ? IosColors.blue : AppColors.control,
            boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x14000000), blurRadius: 14, offset: Offset(0, 5))],
          ),
          child: CustomPaint(
            foregroundPainter: GlassRimPainter(radius),
            child: Center(
              child: busy
                  ? const CupertinoActivityIndicator(color: Colors.white)
                  : Text(
                      label,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: enabled ? Colors.white : IosColors.secondaryLabel,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// Một ô mật khẩu kiểu iOS trong nhóm: chữ gợi ý, ẩn chữ, nút mắt để xem lại
class PasswordField extends StatefulWidget {
  final String placeholder;
  final TextEditingController controller;
  final bool hasError;
  final VoidCallback onChanged;

  const PasswordField({
    super.key,
    required this.placeholder,
    required this.controller,
    required this.hasError,
    required this.onChanged,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool hidden = true;

  @override
  Widget build(BuildContext context) {
    return CupertinoTextField(
      controller: widget.controller,
      obscureText: hidden,
      autocorrect: false,
      enableSuggestions: false,
      placeholder: widget.placeholder,
      placeholderStyle: TextStyle(fontSize: 17, color: IosColors.tertiaryLabel),
      style: TextStyle(fontSize: 17, color: widget.hasError ? IosColors.red : AppColors.text),
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
      decoration: null,
      onChanged: (String _) => widget.onChanged(),
      suffix: CupertinoButton(
        padding: const EdgeInsets.only(right: 12),
        minimumSize: const Size(44, 44),
        onPressed: () => setState(() => hidden = !hidden),
        child: Icon(
          hidden ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
          size: 20,
          color: IosColors.secondaryLabel,
        ),
      ),
    );
  }
}
