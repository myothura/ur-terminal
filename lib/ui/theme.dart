import 'package:flutter/material.dart';
import 'package:xterm2/xterm.dart';

class AppColors {
  AppColors._();

  static const bg = Color(0xFF0D1015);
  static const sidebar = Color(0xFF10141A);
  static const surface = Color(0xFF151A21);
  static const surface2 = Color(0xFF1B212A);
  static const surface3 = Color(0xFF222A35);
  static const border = Color(0xFF262E3A);
  static const text = Color(0xFFE6EAF0);
  static const textMuted = Color(0xFF8C96A6);
  static const textFaint = Color(0xFF5D6778);
  static const accent = Color(0xFF3DDC97);
  static const accentDim = Color(0x333DDC97);
  static const danger = Color(0xFFF26D6D);
  static const warning = Color(0xFFF5B85C);
  static const info = Color(0xFF6CA8FF);
}

const kMonoFont = 'Menlo';
const kMonoFallback = ['SF Mono', 'Monaco', 'Courier New'];

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: AppColors.accent,
    onPrimary: const Color(0xFF06140E),
    surface: AppColors.surface,
    onSurface: AppColors.text,
    error: AppColors.danger,
    outline: AppColors.border,
  );

  OutlineInputBorder border(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    canvasColor: AppColors.surface,
    dividerColor: AppColors.border,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: const Color(0x0DFFFFFF),
    visualDensity: VisualDensity.compact,
    textTheme: const TextTheme(
      titleLarge: TextStyle(
          fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.text),
      titleMedium: TextStyle(
          fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text),
      bodyMedium: TextStyle(fontSize: 13, color: AppColors.text),
      bodySmall: TextStyle(fontSize: 12, color: AppColors.textMuted),
      labelMedium: TextStyle(fontSize: 12, color: AppColors.textMuted),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: AppColors.surface2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      hintStyle: const TextStyle(color: AppColors.textFaint, fontSize: 13),
      labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
      border: border(AppColors.border),
      enabledBorder: border(AppColors.border),
      focusedBorder: border(AppColors.accent),
      errorBorder: border(AppColors.danger),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: const Color(0xFF06140E),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 13),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textMuted,
        textStyle: const TextStyle(fontSize: 13),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.border),
      ),
      textStyle: const TextStyle(fontSize: 13, color: AppColors.text),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.surface3,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      textStyle: const TextStyle(fontSize: 12, color: AppColors.text),
      waitDuration: const Duration(milliseconds: 500),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surface3,
      contentTextStyle: TextStyle(color: AppColors.text, fontSize: 13),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? AppColors.bg : AppColors.textMuted),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.surface3),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(const Color(0x33FFFFFF)),
      thickness: WidgetStateProperty.all(6),
      radius: const Radius.circular(3),
    ),
  );
}

const terminalTheme = TerminalTheme(
  cursor: Color(0xFF3DDC97),
  selection: Color(0x553DDC97),
  foreground: Color(0xFFD9DEE7),
  background: Color(0xFF0D1015),
  black: Color(0xFF1B212A),
  red: Color(0xFFF26D6D),
  green: Color(0xFF3DDC97),
  yellow: Color(0xFFF5B85C),
  blue: Color(0xFF6CA8FF),
  magenta: Color(0xFFC792EA),
  cyan: Color(0xFF5CCFE6),
  white: Color(0xFFD9DEE7),
  brightBlack: Color(0xFF5D6778),
  brightRed: Color(0xFFFF8A8A),
  brightGreen: Color(0xFF6EF0B5),
  brightYellow: Color(0xFFFFD08A),
  brightBlue: Color(0xFF94C0FF),
  brightMagenta: Color(0xFFDDB4FF),
  brightCyan: Color(0xFF8BE3F2),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xFF5A4A1A),
  searchHitBackgroundCurrent: Color(0xFFF5B85C),
  searchHitForeground: Color(0xFF0D1015),
);

const terminalStyle = TerminalStyle(
  fontSize: 13,
  height: 1.25,
  fontFamily: kMonoFont,
  fontFamilyFallback: kMonoFallback,
);
