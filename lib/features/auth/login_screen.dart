import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import 'session_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() {
    return _LoginScreenState();
  }
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  // TextEditingController (Flutter): giữ chữ trong ô nhập, đọc bằng .text
  final TextEditingController identifierController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  // true: đang chờ server thì khóa nút, tránh bấm 2 lần (sai 5 lần là bị khóa 15 phút)
  bool isSubmitting = false;
  // null = không có lỗi
  String? errorText;
  // true: mật khẩu hiện dấu chấm. Bấm con mắt thì đảo lại
  bool hidePassword = true;

  // Rời màn thì giải phóng 2 controller
  @override
  void dispose() {
    identifierController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final String identifier = identifierController.text.trim();
    final String password = passwordController.text;
    if (identifier.isEmpty || password.isEmpty) {
      setState(() {
        errorText = 'Nhập tài khoản và mật khẩu.';
      });
      return;
    }

    //chỉ 1 màn thì setState là đủ nhiều màn mới cần ref của riverpod
    setState(() {
      isSubmitting = true;
      errorText = null;
    });

    try {
      // ref.read: bấm nút chỉ gọi 1 lần. .notifier = người lo việc của hộp (SessionNotifier)
      // Đúng mật khẩu thì hộp có Session, bảo vệ ở router tự đưa vào trong
      await ref.read(sessionProvider.notifier).signIn(identifier, password);
    } catch (error) {
      // mounted (Flutter): màn còn hiển thị không. Sau await phải kiểm rồi mới setState
      if (mounted) {
        setState(() {
          isSubmitting = false;
          errorText = errorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      // bottom: false → tấm trắng kéo sát đáy màn
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Phần xanh: logo + tên app
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 48, 28, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Ô cam bo góc, trong có hình xe tải (Icons có sẵn của Flutter)
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.orange,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.local_shipping_outlined, color: Colors.white),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'LiftMate',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Quản lý vận tải và cẩu lắp máy móc nặng',
                    style: TextStyle(fontSize: 15, color: Color(0xFFC9D2E3)),
                  ),
                ],
              ),
            ),
            // Tấm trắng bo góc trên, chiếm hết phần còn lại (Expanded)
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                // Bàn phím bật lên vẫn cuộn được
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Đăng nhập',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text),
                      ),
                      const SizedBox(height: 18),

                      // Ô tài khoản: nhãn ở trên, ô ở dưới
                      const Text(
                        'Email, tên đăng nhập hoặc số điện thoại',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.label),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: identifierController,
                        // Nút "tiếp" trên bàn phím → nhảy xuống ô mật khẩu
                        textInputAction: TextInputAction.next,
                        // Gợi ý tự điền tài khoản đã lưu của Android
                        autofillHints: const [AutofillHints.username],
                      ),
                      const SizedBox(height: 18),

                      // Ô mật khẩu + nút con mắt
                      const Text(
                        'Mật khẩu',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.label),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: passwordController,
                        obscureText: hidePassword,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        // Bấm "xong" trên bàn phím = bấm nút Đăng nhập
                        onSubmitted: (String value) {
                          submit();
                        },
                        decoration: InputDecoration(
                          // suffixIcon: nút nằm cuối ô
                          suffixIcon: IconButton(
                            // tooltip: đọc cho người khiếm thị + hiện khi nhấn giữ
                            tooltip: hidePassword ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                            icon: Icon(
                              hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              color: AppColors.textMuted,
                            ),
                            onPressed: () {
                              setState(() {
                                hidePassword = !hidePassword;
                              });
                            },
                          ),
                        ),
                      ),

                      // Có lỗi thì mới thêm dòng chữ đỏ
                      if (errorText != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(errorText!, style: const TextStyle(color: AppColors.errorText)),
                        ),

                      // Link quên mật khẩu, nằm bên phải
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            // push: mở chồng lên, quay lại thì về màn đăng nhập
                            context.push('/forgot-password');
                          },
                          child: const Text('Quên mật khẩu?'),
                        ),
                      ),
                      const SizedBox(height: 8),

                      FilledButton(
                        // onPressed = null → nút xám, không bấm được
                        onPressed: isSubmitting ? null : submit,
                        child: Text(isSubmitting ? 'Đang đăng nhập...' : 'Đăng nhập'),
                      ),
                      const SizedBox(height: 32),

                      // Hộp xám: app không có đăng ký, tài khoản do quản lý mời
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Chưa có tài khoản? Tài khoản do quản lý công ty mời qua email. Liên hệ quản lý để được cấp.',
                          style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.5),
                        ),
                      ),
                    ],
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
