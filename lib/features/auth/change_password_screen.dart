// Màn đổi mật khẩu (N5, doc mục 3.5). Hai cách vào:
// 1. Bị bắt đổi (mustChangePassword = true): bảo vệ ở router nhốt ở đây, có hộp vàng + nút Đăng xuất, không có nút quay lại.
// 2. Tự đổi (sau này bấm từ menu): có nút quay lại, đổi xong thì quay về màn trước.
import 'package:flutter/material.dart';
// Riverpod: ConsumerStatefulWidget, ConsumerState, ref
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.canPop, context.pop, context.go
import 'package:go_router/go_router.dart';

import '../../core/api/call.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
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
    if (fieldErrors.containsKey(field)) {
      setState(() {
        fieldErrors.remove(field);
      });
    }
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
        const SnackBar(content: Text('Đã đổi mật khẩu.')),
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
    bool isForced = false;
    if (session != null && session.mustChangePassword) {
      isForced = true;
    }

    String currentLabel = 'Mật khẩu hiện tại';
    if (isForced) {
      currentLabel = 'Mật khẩu hiện tại (mật khẩu tạm)';
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Đổi mật khẩu'),
        // Bị bắt đổi thì không có nút quay lại
        automaticallyImplyLeading: !isForced,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Hộp vàng chỉ hiện khi bị bắt đổi
              if (isForced)
                Container(
                  margin: const EdgeInsets.only(bottom: 18),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.warnBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lock_outline, size: 20, color: AppColors.warnText),
                      SizedBox(width: 10),
                      // Expanded: chữ dài thì xuống dòng thay vì tràn ra ngoài
                      Expanded(
                        child: Text(
                          'Bạn đang dùng mật khẩu tạm. Đặt mật khẩu mới để tiếp tục dùng app.',
                          style: TextStyle(fontSize: 14, color: AppColors.warnText, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),

              PasswordField(
                label: currentLabel,
                controller: currentController,
                errorText: fieldErrors['currentPassword'],
                onChanged: () {
                  clearFieldError('currentPassword');
                },
              ),
              const SizedBox(height: 18),
              PasswordField(
                label: 'Mật khẩu mới',
                controller: newController,
                errorText: fieldErrors['newPassword'],
                onChanged: () {
                  clearFieldError('newPassword');
                },
              ),
              const SizedBox(height: 18),
              PasswordField(
                label: 'Nhập lại mật khẩu mới',
                controller: confirmController,
                errorText: fieldErrors['confirmPassword'],
                onChanged: () {
                  clearFieldError('confirmPassword');
                },
              ),

              if (errorText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(errorText!, style: const TextStyle(color: AppColors.errorText)),
                ),
              const SizedBox(height: 24),

              FilledButton(
                onPressed: isSubmitting ? null : submit,
                child: Text(isSubmitting ? 'Đang đổi...' : 'Đổi mật khẩu'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Đổi xong, các máy khác đang đăng nhập tài khoản này sẽ bị đăng xuất.',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.5),
              ),

              // Bị bắt đổi mà không muốn đổi lúc này thì vẫn phải thoát ra được
              if (isForced)
                Padding(
                  padding: const EdgeInsets.only(top: 32),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: isSubmitting
                        ? null
                        : () {
                            // Hộp thành null thì bảo vệ ở router đưa về /login
                            ref.read(sessionProvider.notifier).signOut();
                          },
                    child: const Text('Đăng xuất'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Một ô mật khẩu: nhãn ở trên, ô ẩn chữ, lỗi đỏ ở dưới ô (nếu có)
class PasswordField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? errorText;
  final VoidCallback onChanged;

  const PasswordField({
    super.key,
    required this.label,
    required this.controller,
    required this.errorText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.label),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: true,
          onChanged: (String value) {
            onChanged();
          },
          // errorText (Flutter): khác null thì viền đỏ + chữ đỏ dưới ô
          decoration: InputDecoration(errorText: errorText),
        ),
      ],
    );
  }
}
