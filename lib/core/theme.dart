import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color navy = Color(0xFF0C2858);        // nút chính, chữ nhấn
  static const Color navyLight = Color(0xFFEEF2F9);   // nền mục đang chọn
  static const Color orange = Color(0xFFEC7C34);      // USP (AI, 3D), logo
  static const Color text = Color(0xFF101828);        // chữ chính
  static const Color textMuted = Color(0xFF5B6576);   // chữ phụ
  static const Color label = Color(0xFF344054);       // nhãn trên ô nhập
  static const Color border = Color(0xFFEAECF0);      // viền thẻ
  static const Color inputBorder = Color(0xFFD0D5DD); // viền ô nhập
  static const Color background = Color(0xFFF7F8FA);  // nền màn
  static const Color okText = Color(0xFF0F7B45);      // Đạt
  static const Color okBackground = Color(0xFFE8F5EE);
  static const Color warnText = Color(0xFF8A5C00);    // Nhắc
  static const Color warnBackground = Color(0xFFFFF6DB);
  static const Color errorText = Color(0xFFB42318);   // Chặn, lỗi
  static const Color errorBackground = Color(0xFFFDECEA);
}

// Thanh trạng thái cho màn nền trắng: trong suốt, chữ tối
const SystemUiOverlayStyle whiteScreenStatusBar = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
);

// Kiểu thanh trạng thái còn nguyên sau khi rời màn: trả lại mặc định của Android (lớp phủ mờ, chữ sáng)
void restoreDefaultStatusBar() {
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0x40000000),
    statusBarIconBrightness: Brightness.light,
  ));
}

ThemeData appTheme() {
  // Viền ô nhập: bo 10, màu xám
  final OutlineInputBorder inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: const BorderSide(color: AppColors.inputBorder),
  );
  // Ô đang gõ: viền xanh đậm
  final OutlineInputBorder focusedBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: const BorderSide(color: AppColors.navy, width: 1.5),
  );

  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.navy,
      primary: AppColors.navy,
      error: AppColors.errorText,
    ),
    scaffoldBackgroundColor: AppColors.background,
    // Mọi chữ trong app dùng Be Vietnam Pro
    fontFamily: GoogleFonts.beVietnamPro().fontFamily,
    // Mọi TextField: nền trắng, bo 10, viền xám
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: focusedBorder,
    ),
    // Mọi FilledButton: cao 48, bo 10, chữ đậm
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
