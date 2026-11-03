import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'widgets/page_transition.dart';

/// Màu theo chế độ sáng / tối của hệ thống. [isDark] do LiftmateApp cập nhật; đổi chế độ thì dựng lại cả cây widget.
/// Màu đọc lúc build, nên không gán vào hằng hay biến static final.
class AppColors {
  static bool isDark = false;

  static Color _pick(int light, int dark) => Color(isDark ? dark : light);

  // Chế độ tối dùng cam thương hiệu làm màu nhấn: navy tối không đọc được trên nền tối
  static Color get navy => _pick(0xFF0C2858, 0xFFF28C3C);        // nút chính, chữ nhấn
  static Color get navyLight => _pick(0xFFEEF2F9, 0xFF3A2414);   // nền mục đang chọn
  static const Color orange = Color(0xFFEC7C34);                 // USP (AI, 3D), logo
  static Color get text => _pick(0xFF101828, 0xFFF2F4F7);        // chữ chính
  static Color get textMuted => _pick(0xFF5B6576, 0xFF9BA4B4);   // chữ phụ
  static Color get label => _pick(0xFF344054, 0xFFD0D5DD);       // nhãn trên ô nhập
  static Color get border => _pick(0xFFEAECF0, 0xFF2C2C2E);      // viền thẻ
  static Color get inputBorder => _pick(0xFFD0D5DD, 0xFF48484A); // viền ô nhập
  static Color get background => _pick(0xFFF7F8FA, 0xFF000000);  // nền màn
  static Color get surface => _pick(0xFFFFFFFF, 0xFF1C1C1E);     // nền thẻ, ô nhập
  static Color get raised => _pick(0xFFFFFFFF, 0xFF2C2C2E);      // thẻ nổi trên sheet kính
  static Color get glass => _pick(0xFFFFFFFF, 0xFF1C1C1E);       // lớp phủ của kính
  static Color get fillSoft => _pick(0xFFF2F4F7, 0xFF2C2C2E);    // nền nhãn, ô phụ
  static Color get hairline => _pick(0xFFE5E5EA, 0xFF38383A);    // đường kẻ mảnh
  static Color get control => _pick(0xFFC7C7CC, 0xFF636366);     // viền ô chọn chưa bật
  static Color get okText => _pick(0xFF0F7B45, 0xFF4ADE80);      // Đạt
  static Color get okBackground => _pick(0xFFE8F5EE, 0xFF12301F);
  static Color get warnText => _pick(0xFF8A5C00, 0xFFF5C451);    // Nhắc
  static Color get warnBackground => _pick(0xFFFFF6DB, 0xFF33270A);
  static Color get warmText => _pick(0xFFB4541A, 0xFFF4A261);    // chữ cam trên nền thẻ
  static Color get warmBackground => _pick(0xFFFFF8F2, 0xFF33210F);
  static Color get errorText => _pick(0xFFB42318, 0xFFFF8A80);   // Chặn, lỗi
  static Color get errorBackground => _pick(0xFFFDECEA, 0xFF3A1614);
  static Color get errorBorder => _pick(0xFFF3B5AE, 0xFF7A2E27);
}

// Thanh trạng thái cho màn nền trắng (chế độ tối thì nền tối): trong suốt, chữ tương phản
SystemUiOverlayStyle get whiteScreenStatusBar => SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: AppColors.isDark ? Brightness.light : Brightness.dark,
  statusBarBrightness: AppColors.isDark ? Brightness.dark : Brightness.light,
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
    borderSide: BorderSide(color: AppColors.inputBorder),
  );
  // Ô đang gõ: viền xanh đậm
  final OutlineInputBorder focusedBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(color: AppColors.navy, width: 1.5),
  );

  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      brightness: AppColors.isDark ? Brightness.dark : Brightness.light,
      seedColor: AppColors.navy,
      primary: AppColors.navy,
      onPrimary: Colors.white,
      error: AppColors.errorText,
      surface: AppColors.surface,
      onSurface: AppColors.text,
    ),
    // Bánh xe chọn ngày, nút Cupertino, viền ... theo cùng chế độ
    brightness: AppColors.isDark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: AppColors.background,
    // Mọi trang mở bằng builder của go_router đều chuyển cảnh cùng một kiểu
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.iOS: AppPageTransitions(),
        TargetPlatform.android: AppPageTransitions(),
      },
    ),
    // Mọi chữ trong app dùng Be Vietnam Pro
    fontFamily: GoogleFonts.beVietnamPro().fontFamily,
    // Mọi TextField: nền trắng, bo 10, viền xám
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
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
