import 'dart:io';
import 'dart:ui';

import 'package:flutter/cupertino.dart' show CupertinoButton;
import 'package:flutter/material.dart';
// SystemUiOverlayStyle: chữ thanh trạng thái màu tối trên nền trắng
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// go_router: context.push
import 'package:go_router/go_router.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/ios.dart';
import '../../core/widgets/liftmate_mark.dart';
import '../dashboard/home_cover.dart';
import 'app_lock.dart';
import 'ripple_transition.dart';
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
  bool biometricBusy = false;
  bool autoPromptDone = false;
  final GlobalKey biometricButtonKey = GlobalKey();
  // Giữ người đang khóa sau khi mở khóa: màn còn trượt đi vài khung, không được nháy sang biểu mẫu thường
  Session? shownLocked;
  File? coverImage;
  bool coverReady = false;

  @override
  void initState() {
    super.initState();
    // Đang khóa app: mở Face ID ngay, không bắt bấm thêm
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted || lockedSession == null) return;
      loadCover(lockedSession!.userId);
      final Animation<double>? route = ModalRoute.of(context)?.animation;
      if (route == null || route.isCompleted) {
        promptOnce();
        return;
      }
      // Đợi màn hiện xong rồi mới hỏi, để hộp Face ID không đè lên hoạt ảnh
      void onStatus(AnimationStatus status) {
        if (status != AnimationStatus.completed) return;
        route.removeStatusListener(onStatus);
        promptOnce();
      }

      route.addStatusListener(onStatus);
    });
  }

  Future<void> loadCover(String userId) async {
    final File? image = await HomeCoverStore.resolve(userId);
    if (!mounted) return;
    // Giải mã sẵn để trang chủ lộ ra theo vòng lan đã có ảnh
    if (image != null) precacheImage(FileImage(image), context, onError: (Object error, StackTrace? stack) {});
    setState(() {
      coverImage = image;
      coverReady = true;
    });
  }

  /// Phiên đang bị khóa; null là màn đăng nhập bình thường
  Session? get lockedSession {
    final Session? session = ref.read(sessionProvider).value;
    return (ref.read(appLockProvider).value?.blocks(session) ?? false) ? session : null;
  }

  Future<void> promptOnce() async {
    if (!mounted || autoPromptDone) return;
    autoPromptDone = true;
    // Máy chưa cài Face ID, vân tay thì không hỏi; màn hiện lời nhắc dùng mật khẩu
    final BiometricKind kind = await ref.read(biometricKindProvider.future);
    if (mounted && kind.isUsable) unlockWithBiometric();
  }

  Future<void> unlockWithBiometric() async {
    if (biometricBusy) return;
    setState(() {
      biometricBusy = true;
      errorText = null;
    });
    final BiometricResult result = await ref.read(biometricAuthProvider).authenticate();
    if (!mounted) return;
    setState(() {
      biometricBusy = false;
      if (result == BiometricResult.failed) errorText = t('appLock.failed');
    });
    if (result != BiometricResult.success) return;
    // Trang chủ lan ra từ nút Face ID. Phải đổi mật khẩu thì sang màn khác, không có chuyển cảnh lan
    if (shownLocked?.mustChangePassword == false) pendingRippleOrigin = biometricButtonCenter();
    // Mở khóa thì bảo vệ ở router tự đưa vào trong
    ref.read(appLockProvider.notifier).unlock();
  }

  Offset? biometricButtonCenter() {
    final RenderObject? box = biometricButtonKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  // Rời màn thì giải phóng 2 controller
  @override
  void dispose() {
    identifierController.dispose();
    passwordController.dispose();
    restoreDefaultStatusBar();
    super.dispose();
  }

  // Tài khoản của người đang khóa: màn khóa không có ô này
  String lockedIdentifier(Session session) {
    if (session.username.isNotEmpty) return session.username;
    if ((session.email ?? '').isNotEmpty) return session.email!;
    return session.phone;
  }

  Future<void> submit() async {
    final Session? locked = shownLocked;
    final String identifier = locked == null ? identifierController.text.trim() : lockedIdentifier(locked);
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
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: logoNavy, width: 1.5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Vẽ lại khi trạng thái khóa đổi
    ref.watch(appLockProvider);
    final Session? session = ref.watch(sessionProvider).value;
    final Session? locked = lockedSession;
    if (locked != null) {
      shownLocked = locked;
    } else if (session == null) {
      shownLocked = null;
    }
    if (shownLocked != null) return buildLockedScreen(shownLocked!);
    // Đồng hồ chuyển màn: logo bay sang trước, phần nhập hiện lên và trượt nhẹ theo sau
    final Animation<double> route = ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation;
    const Curve revealCurve = Interval(0.6, 1, curve: Curves.easeOutCubic);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: whiteScreenStatusBar,
      child: Scaffold(
        backgroundColor: AppColors.surface,
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
                    Center(
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

  Future<void> useOtherAccount() async {
    final bool confirmed = await showIosConfirm(
      context,
      title: t('appLock.otherAccountTitle'),
      message: t('appLock.otherAccountMessage'),
      action: t('appLock.otherAccount'),
    );
    if (!confirmed || !mounted) return;
    passwordController.clear();
    setState(() => errorText = null);
    await ref.read(sessionProvider.notifier).signOut();
  }

  // Màn khóa: thẻ kính trên nền ảnh bìa của người dùng
  Widget buildLockedScreen(Session session) {
    final Animation<double> route = ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation;
    final bool dark = AppColors.isDark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedOpacity(
              opacity: coverReady ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: coverImage != null
                  ? Image.file(
                      coverImage!,
                      fit: BoxFit.cover,
                      errorBuilder: (BuildContext context, Object error, StackTrace? stack) => CustomPaint(painter: DefaultCoverPainter(dark: dark)),
                    )
                  : CustomPaint(painter: DefaultCoverPainter(dark: dark)),
            ),
            // Phủ nhẹ ở đỉnh để giờ và pin đọc được trên mọi ảnh
            Align(
              alignment: Alignment.topCenter,
              child: IgnorePointer(
                child: Container(
                  height: MediaQuery.paddingOf(context).top + 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[IosColors.groupedBackground.withValues(alpha: 0.6), IosColors.groupedBackground.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: FadeTransition(
                    opacity: route.drive(CurveTween(curve: const Interval(0.5, 1, curve: Curves.easeOut))),
                    child: buildLockedCard(session),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildLockedCard(Session session) {
    final BiometricKind? kind = ref.watch(biometricKindProvider).value;
    const BorderRadius corners = BorderRadius.all(Radius.circular(28));
    return ClipRRect(
      borderRadius: corners,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          foregroundDecoration: BoxDecoration(
            borderRadius: corners,
            border: Border.all(color: Colors.white.withValues(alpha: AppColors.isDark ? 0.22 : 0.65)),
          ),
          color: AppColors.surface.withValues(alpha: 0.72),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Hero(tag: markHeroTag, child: LiftMateMark(height: 52)),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t('appLock.hello'), style: TextStyle(fontSize: 17, color: AppColors.text)),
                              const SizedBox(height: 6),
                              Text(
                                session.fullName,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 34, height: 1.15, fontWeight: FontWeight.w300, letterSpacing: -0.4, color: AppColors.text),
                              ),
                            ],
                          ),
                        ),
                        if (kind != null && kind.isUsable) ...[
                          const SizedBox(width: 12),
                          buildBiometricButton(kind),
                        ],
                      ],
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: passwordController,
                      obscureText: hidePassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (String value) {
                        submit();
                      },
                      decoration: InputDecoration(
                        hintText: t('login.password'),
                        filled: false,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        border: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textMuted.withValues(alpha: 0.5))),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.navy, width: 1.5)),
                        suffixIcon: IconButton(
                          tooltip: hidePassword ? t('login.showPassword') : t('login.hidePassword'),
                          icon: Icon(hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: AppColors.textMuted),
                          onPressed: () {
                            setState(() {
                              hidePassword = !hidePassword;
                            });
                          },
                        ),
                      ),
                    ),
                    if (errorText != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(errorText!, style: TextStyle(fontSize: 14, color: AppColors.errorText)),
                      ),
                    if (kind != null && !kind.isUsable)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(t('appLock.unavailable'), style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.4)),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: CupertinoButton(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(44, 44),
                            onPressed: isSubmitting ? null : useOtherAccount,
                            child: Text(
                              t('appLock.otherAccount'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: CupertinoButton(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(44, 44),
                            onPressed: () {
                              context.push('/forgot-password');
                            },
                            child: Text(
                              t('login.forgot'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Semantics(
                button: true,
                child: Material(
                  color: AppColors.isDark ? AppColors.navy : logoNavy,
                  child: InkWell(
                    onTap: isSubmitting ? null : submit,
                    child: SizedBox(
                      height: 60,
                      child: Center(
                        child: Text(
                          isSubmitting ? t('login.signingIn') : t('login.signIn'),
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildBiometricButton(BiometricKind kind) {
    return Semantics(
      button: true,
      label: t('appLock.unlockWith', <String, Object?>{'name': kind.displayName}),
      child: IosPressBounce(
        child: GestureDetector(
          onTap: biometricBusy ? null : unlockWithBiometric,
          child: Container(
            key: biometricButtonKey,
            width: 60,
            height: 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (AppColors.isDark ? AppColors.navy : logoNavy).withValues(alpha: biometricBusy ? 0.45 : 0.9),
            ),
            child: BiometricIcon(kind: kind, size: 34, color: Colors.white),
          ),
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
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 28),
        Text(
          t('login.title'),
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: AppColors.text),
        ),
        const SizedBox(height: 18),

        // Ô tài khoản: nhãn ở trên, ô ở dưới
        Text(
          t('login.identifier'),
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.label),
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
            child: Text(errorText!, style: TextStyle(color: AppColors.errorText)),
          ),

        // Link quên mật khẩu, nằm bên phải. Màu cam đậm của web để đọc rõ trên nền trắng
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.warmText),
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
            backgroundColor: AppColors.isDark ? AppColors.navy : logoNavy,
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
            style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.5),
          ),
        ),
      ],
    );
  }
}
