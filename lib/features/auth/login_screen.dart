import 'package:flutter/material.dart';
// SystemUiOverlayStyle: chữ thanh trạng thái màu tối trên nền trắng
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push
import 'package:go_router/go_router.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/liftmate_mark.dart';
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
    restoreDefaultStatusBar();
    super.dispose();
  }

  Future<void> submit() async {
    final String identifier = identifierController.text.trim();
    final String password = passwordController.text;
    if (identifier.isEmpty || password.isEmpty) {
      setState(() {
        errorText = t('login.missingFields');
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

  // Ô nhập theo phong cách web: nền xám rất nhạt, bo 14, viền mảnh
  InputDecoration fieldDecoration({Widget? suffixIcon}) {
    final BorderRadius radius = BorderRadius.circular(14);
    return InputDecoration(
      filled: true,
      fillColor: AppColors.background,
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: logoNavy, width: 1.5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Đồng hồ chuyển màn: logo bay sang trước, phần nhập hiện lên và trượt nhẹ theo sau
    final Animation<double> route = ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation;
    const Curve revealCurve = Interval(0.6, 1, curve: Curves.easeOutCubic);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: whiteScreenStatusBar,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const LiftMateSparks(startAt: 1.35),
            SafeArea(
              // Bàn phím bật lên vẫn cuộn được
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo + tên app, giống màn khởi động và đầu trang web
                    const Center(
                      child: Hero(tag: markHeroTag, child: LiftMateMark(height: 116)),
                    ),
                    const SizedBox(height: 2),
                    const Center(
                      child: Hero(tag: wordHeroTag, child: LiftMateWord(fontSize: 34)),
                    ),
                    FadeTransition(
                      opacity: route.drive(CurveTween(curve: revealCurve)),
                      child: SlideTransition(
                        position: route.drive(
                          Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
                              .chain(CurveTween(curve: revealCurve)),
                        ),
                        child: buildForm(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(
          t('login.tagline'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 28),
        Text(
          t('login.title'),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: AppColors.text),
        ),
        const SizedBox(height: 18),

        // Ô tài khoản: nhãn ở trên, ô ở dưới
        Text(
          t('login.identifier'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.label),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: identifierController,
          // Nút "tiếp" trên bàn phím → nhảy xuống ô mật khẩu
          textInputAction: TextInputAction.next,
          // Gợi ý tự điền tài khoản đã lưu của Android
          autofillHints: const [AutofillHints.username],
          decoration: fieldDecoration(),
        ),
        const SizedBox(height: 16),

        // Ô mật khẩu + nút con mắt
        Text(
          t('login.password'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.label),
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
          decoration: fieldDecoration(
            // suffixIcon: nút nằm cuối ô
            suffixIcon: IconButton(
              // tooltip: đọc cho người khiếm thị + hiện khi nhấn giữ
              tooltip: hidePassword ? t('login.showPassword') : t('login.hidePassword'),
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

        // Link quên mật khẩu, nằm bên phải. Màu cam đậm của web để đọc rõ trên nền trắng
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFB4500E)),
            onPressed: () {
              // push: mở chồng lên, quay lại thì về màn đăng nhập
              context.push('/forgot-password');
            },
            child: Text(t('login.forgot')),
          ),
        ),
        const SizedBox(height: 4),

        // Nút bo tròn hẳn như các nút trên web
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: logoNavy,
            minimumSize: const Size.fromHeight(52),
            shape: const StadiumBorder(),
          ),
          // onPressed = null → nút xám, không bấm được
          onPressed: isSubmitting ? null : submit,
          child: Text(isSubmitting ? t('login.signingIn') : t('login.signIn')),
        ),
        const SizedBox(height: 20),

        // Hộp xám: app không có đăng ký, tài khoản do quản lý mời
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            t('login.noAccount'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.5),
          ),
        ),
      ],
    );
  }
}
