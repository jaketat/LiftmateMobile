// Màn quên mật khẩu (A1, doc mục 3.6). Chỉ gửi email; đặt mật khẩu mới làm trên web qua link trong thư.
import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import 'auth_api.dart';

// StatefulWidget thường (không cần ref): màn này không đọc hộp session nào
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() {
    return _ForgotPasswordScreenState();
  }
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController emailController = TextEditingController();
  bool isSubmitting = false;
  // true: đã gửi xong, hiện khung xanh
  bool isSent = false;
  String? errorText;

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final String email = emailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        errorText = t('forgotPassword.missingEmail');
      });
      return;
    }

    setState(() {
      isSubmitting = true;
      errorText = null;
      isSent = false;
    });

    try {
      await forgotPassword(email);
      if (!mounted) {
        return;
      }
      setState(() {
        isSubmitting = false;
        isSent = true;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        isSubmitting = false;
        // Gửi quá nhiều lần (429) hoặc mất mạng: hiện câu lỗi
        errorText = errorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      // Mở bằng push từ màn đăng nhập nên AppBar tự có nút quay lại
      appBar: AppBar(title: Text(t('forgotPassword.title'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('forgotPassword.intro'),
                style: TextStyle(fontSize: 15, color: AppColors.label, height: 1.6),
              ),
              const SizedBox(height: 18),
              Text(
                t('forgotPassword.email'),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.label),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: emailController,
                // Bàn phím có sẵn chữ @
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.send,
                onSubmitted: (String value) {
                  submit();
                },
              ),
              if (errorText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(errorText!, style: TextStyle(color: AppColors.errorText)),
                ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: isSubmitting ? null : submit,
                child: Text(isSubmitting ? t('common.sending') : t('forgotPassword.send')),
              ),

              // Khung xanh sau khi gửi: luôn cùng một câu, kể cả email không tồn tại
              if (isSent)
                Container(
                  margin: const EdgeInsets.only(top: 18),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.okBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check, size: 20, color: AppColors.okText),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t('forgotPassword.sent'),
                          style: TextStyle(fontSize: 14, color: AppColors.okText, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 32),
              // Hộp xám cho người không có email (vd tài xế)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text.rich(
                  // Text.rich (Flutter): một đoạn chữ có phần in đậm, phần thường
                  TextSpan(
                    children: [
                      TextSpan(text: '${t('forgotPassword.noEmailTitle')} ', style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: t('forgotPassword.noEmailMessage')),
                    ],
                  ),
                  style: TextStyle(fontSize: 14, color: AppColors.label, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
