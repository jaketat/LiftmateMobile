// Màn chờ lúc mở app: hộp session đang hỏi server. Mất mạng thì hiện lỗi + "Thử lại".
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
// Riverpod: ConsumerWidget, WidgetRef, AsyncValue
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/async_view.dart';
import 'session_provider.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Nhìn hộp + nghe chuông: hộp đổi từ "đang tải" sang "lỗi" thì màn tự vẽ lại
    final AsyncValue<Session?> sessionValue = ref.watch(sessionProvider);

    // Lỗi (mất mạng, server bận): token vẫn giữ, bấm Thử lại là hỏi lại server
    if (sessionValue.hasError) {
      return Scaffold(
        // ErrorView (core/widgets/async_view.dart): câu lỗi + nút "Thử lại"
        body: ErrorView(
          message: errorMessage(sessionValue.error!),
          onRetry: () {
            // ref.invalidate (Riverpod): đổ hộp đi → build() của SessionNotifier chạy lại
            ref.invalidate(sessionProvider);
          },
        ),
      );
    }

    // Đang tải: nền xanh + vòng xoay
    return const Scaffold(
      backgroundColor: AppColors.navy,
      body: Center(child: CupertinoActivityIndicator(color: Colors.white, radius: 14)),
    );
  }
}