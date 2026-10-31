// Màn đổi mật khẩu (N5, doc mục 3.5). Hai cách vào:
// 1. Bị bắt đổi (mustChangePassword = true): bảo vệ ở router nhốt ở đây, có hộp vàng + nút Đăng xuất, không có nút quay lại.
// 2. Tự đổi (sau này bấm từ menu): có nút quay lại, đổi xong thì quay về màn trước.
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('password.changed'))),
      );
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

    return IosPage(
      title: t('password.title'),
      // Bị bắt đổi thì không có nút quay lại
      showBack: !isForced,
      slivers: <Widget>[
        if (isForced)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: IosColors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Icon(CupertinoIcons.lock_shield_fill, size: 20, color: AppColors.warnText),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t('password.temporaryNotice'),
                        style: const TextStyle(fontSize: 15, color: AppColors.warnText, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: IosGroup(
            header: t('password.current'),
            footerWidget: _errorText(fieldErrors['currentPassword']),
            children: <Widget>[
              PasswordField(
                placeholder: isForced ? t('password.temporary') : t('password.required'),
                controller: currentController,
                hasError: fieldErrors['currentPassword'] != null,
                onChanged: () => clearFieldError('currentPassword'),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: IosGroup(
            header: t('password.new'),
            // Lỗi của ô thì ghi đỏ dưới nhóm, không lỗi thì ghi chú
            footerWidget: (fieldErrors['newPassword'] ?? fieldErrors['confirmPassword']) != null
                ? _errorText(fieldErrors['newPassword'] ?? fieldErrors['confirmPassword'])
                : Text(
                    t('password.signOutOthers'),
                    style: const TextStyle(fontSize: 13, color: IosColors.secondaryLabel, height: 1.35),
                  ),
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
        ),
        if (errorText != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
              child: Text(errorText!, style: const TextStyle(fontSize: 14, color: IosColors.red)),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: IosPillButton(
              label: isSubmitting ? t('common.saving') : t('password.title'),
              busy: isSubmitting,
              onPressed: ready ? submit : null,
            ),
          ),
        ),
        // Bị bắt đổi mà không muốn đổi lúc này thì vẫn phải thoát ra được
        if (isForced)
          SliverToBoxAdapter(
            child: IosGroup(
              children: <Widget>[
                IosRow(
                  title: t('common.signOut'),
                  destructive: true,
                  centered: true,
                  onTap: isSubmitting ? null : () => ref.read(sessionProvider.notifier).signOut(),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget? _errorText(String? text) {
    if (text == null) return null;
    return Text(text, style: const TextStyle(fontSize: 13, color: IosColors.red, height: 1.35));
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
      placeholderStyle: const TextStyle(fontSize: 17, color: IosColors.tertiaryLabel),
      style: TextStyle(fontSize: 17, color: widget.hasError ? IosColors.red : AppColors.text),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
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
