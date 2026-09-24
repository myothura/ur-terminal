import 'package:flutter/material.dart';
import 'package:xterm2/xterm.dart';

class AppColors {
  AppColors._();

  // Neutral graphite, matching macOS Terminal's dark profile.
  static const bg = Color(0xFF1E1E1E);
  static const sidebar = Color(0xFF232323);
  static const surface = Color(0xFF2A2A2A);
  static const surface2 = Color(0xFF323232);
  static const surface3 = Color(0xFF3B3B3B);
  static const border = Color(0xFF3A3A3A);
  static const text = Color(0xFFEDEDED);
  static const textMuted = Color(0xFF9E9E9E);
  static const textFaint = Color(0xFF6E6E6E);

  // Translucent tints laid over the native window blur (glass).
  static const glassChrome = Color(0x99202020);
  static const glassSidebar = Color(0x8C1E1E1E);
  static const glassPage = Color(0xD91E1E1E);
  static const glassBorder = Color(0x40FFFFFF);
  static const accent = Color(0xFF3DDC97);
  static const accentDim = Color(0x333DDC97);
  static const danger = Color(0xFFF26D6D);
  static const warning = Color(0xFFF5B85C);
  static const info = Color(0xFF6CA8FF);
}

const kMonoFont = 'JetBrainsMono';
/// Myanmar fonts that ship with macOS come right after the Latin mono fonts
/// so Burmese text renders instead of tofu boxes.
const kMonoFallback = [
  'Menlo',
  'Myanmar Sangam MN',
  'Myanmar MN',
  'Noto Sans Myanmar',
  'Apple Color Emoji',
];

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
    scaffoldBackgroundColor: Colors.transparent,
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

/// macOS Terminal.app palette (Basic profile, dark appearance).
const terminalTheme = TerminalTheme(
  cursor: Color(0xFFC7C7C7),
  selection: Color(0x66B4D5FF),
  foreground: Color(0xFFF2F2F2),
  background: Color(0xFF1E1E1E),
  black: Color(0xFF000000),
  red: Color(0xFFC23621),
  green: Color(0xFF25BC24),
  yellow: Color(0xFFADAD27),
  blue: Color(0xFF6A7EFF),
  magenta: Color(0xFFD338D3),
  cyan: Color(0xFF33BBC8),
  white: Color(0xFFCBCCCD),
  brightBlack: Color(0xFF818383),
  brightRed: Color(0xFFFC391F),
  brightGreen: Color(0xFF31E722),
  brightYellow: Color(0xFFEAEC23),
  brightBlue: Color(0xFF8C7BFF),
  brightMagenta: Color(0xFFF935F8),
  brightCyan: Color(0xFF14F0F0),
  brightWhite: Color(0xFFE9EBEB),
  searchHitBackground: Color(0xFF6B5A1E),
  searchHitBackgroundCurrent: Color(0xFFF5B85C),
  searchHitForeground: Color(0xFF1E1E1E),
);

const terminalStyle = TerminalStyle(
  fontSize: 13,
  height: 1.35,
  fontFamily: kMonoFont,
  fontFamilyFallback: kMonoFallback,
);
