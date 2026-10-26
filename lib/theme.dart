import 'package:flutter/material.dart';

/// Bảng màu lấy từ bản thiết kế đã duyệt.
class AppColors {
  static const accent = Color(0xFF0F766E);
  static const accentSoft = Color(0x1F0F766E);
  static const background = Color(0xFFF4F5F7);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF16181D);
  static const muted = Color(0xFF5B6270);
  static const line = Color(0xFFE4E7EC);
  static const divider = Color(0xFFEEF0F3);
  static const track = Color(0xFFEEF0F3);
  static const danger = Color(0xFFB42318);

  /// Tiền vào (số dương trong lịch sử nguồn tiền) và nền nhạt đi kèm.
  static const income = Color(0xFF15803D);
  static const incomeSoft = Color(0xFFE8F5EC);

  /// Màu xám trung tính cho biểu tượng "Khác", chuyển tiền, điều chỉnh số dư.
  static const neutral = Color(0xFF475569);
  static const neutralSoft = Color(0xFFEEF1F4);

  /// Nền ô / dòng đang được chọn (màu chủ đạo 8%).
  static const selectedFill = Color(0x140F766E);

  /// Rãnh của nút chọn hai lựa chọn (Thêm tiền | Chuyển tiền).
  static const segmentTrack = Color(0xFFE9EBEF);

  /// Thanh % hạn mức thẻ tín dụng đã dùng (chuyển sang [danger] khi từ 90 % trở lên).
  static const creditBar = Color(0xFFC2410C);

  /// Nền nhạt của cảnh báo đỏ (vượt hạn mức).
  static const dangerSoft = Color(0xFFFEF3F2);

  /// Gạch chân ô nhập phụ (Tổng hạn mức) và nền ô xám nhạt (khung "App tự tính").
  static const lineStrong = Color(0xFFC4C9D2);
  static const fieldFill = Color(0xFFF8F9FA);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    primary: AppColors.accent,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'BeVietnamPro',
    scaffoldBackgroundColor: AppColors.background,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.ink,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: 'BeVietnamPro',
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.accentSoft,
      height: 72,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? AppColors.accent : AppColors.muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: 'BeVietnamPro',
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? AppColors.accent : AppColors.muted,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontFamily: 'BeVietnamPro', fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: Color(0xFFD0D5DD), width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontFamily: 'BeVietnamPro', fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
