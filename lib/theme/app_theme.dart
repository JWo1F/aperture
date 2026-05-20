import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// "Aperture" — Linear-style restraint with macOS-native polish, available
/// in dark (default) and light variants. Both lean on the same indigo accent
/// and hairline borders; only the surface tones invert.
enum AppBrightness { dark, light }

/// Immutable color set. The active palette is swapped on the [AppColors]
/// shim at runtime, so widget call-sites can keep writing `AppColors.bg`
/// without threading a theme object through every constructor.
class Palette {
  const Palette({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceHover,
    required this.sidebarTint,
    required this.sidebarRowHover,
    required this.sidebarRowActive,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentHover,
    required this.accentSoft,
    required this.success,
    required this.error,
    required this.warning,
    required this.info,
    required this.sqlKeyword,
    required this.sqlString,
    required this.sqlNumber,
    required this.sqlComment,
    required this.sqlFunction,
    required this.sqlIdentifier,
  });

  final AppBrightness brightness;

  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color surfaceHover;

  final Color sidebarTint;
  final Color sidebarRowHover;
  final Color sidebarRowActive;

  final Color border;
  final Color borderStrong;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  final Color accent;
  final Color accentHover;
  final Color accentSoft;

  final Color success;
  final Color error;
  final Color warning;
  final Color info;

  final Color sqlKeyword;
  final Color sqlString;
  final Color sqlNumber;
  final Color sqlComment;
  final Color sqlFunction;
  final Color sqlIdentifier;
}

const Palette darkPalette = Palette(
  brightness: AppBrightness.dark,
  bg: Color(0xFF0E1014),
  surface: Color(0xFF16181C),
  surfaceAlt: Color(0xFF1B1E23),
  surfaceHover: Color(0xFF22262C),
  sidebarTint: Color(0xFF13151A),
  sidebarRowHover: Color(0xFF1D2027),
  sidebarRowActive: Color(0x335B7CFA),
  border: Color(0xFF24272D),
  borderStrong: Color(0xFF2F333B),
  textPrimary: Color(0xFFE9EAEC),
  textSecondary: Color(0xFF9BA1AB),
  textMuted: Color(0xFF5C636E),
  accent: Color(0xFF5B7CFA),
  accentHover: Color(0xFF7D97FF),
  accentSoft: Color(0x335B7CFA),
  success: Color(0xFF34D399),
  error: Color(0xFFFB7185),
  warning: Color(0xFFFBBF24),
  info: Color(0xFF60A5FA),
  sqlKeyword: Color(0xFF93B4FF),
  sqlString: Color(0xFFA3E1B0),
  sqlNumber: Color(0xFFE8B583),
  sqlComment: Color(0xFF5C636E),
  sqlFunction: Color(0xFFC4A7FF),
  sqlIdentifier: Color(0xFFE9EAEC),
);

/// Off-white "paper" surface with the same indigo accent. The bg is a touch
/// cooler than pure white so adjacent surfaces (white) read as elevated
/// rather than identical, the way Linear and Things layer their light mode.
const Palette lightPalette = Palette(
  brightness: AppBrightness.light,
  bg: Color(0xFFF4F5F7),
  surface: Color(0xFFFFFFFF),
  surfaceAlt: Color(0xFFF0F1F4),
  surfaceHover: Color(0xFFE7E9ED),
  sidebarTint: Color(0xFFFAFBFC),
  sidebarRowHover: Color(0xFFEDEFF3),
  sidebarRowActive: Color(0x224F6FE8),
  border: Color(0xFFE2E4E9),
  borderStrong: Color(0xFFCBCED5),
  textPrimary: Color(0xFF15171C),
  textSecondary: Color(0xFF5A6170),
  textMuted: Color(0xFF98A0AC),
  accent: Color(0xFF4F6FE8),
  accentHover: Color(0xFF3A5BD9),
  accentSoft: Color(0x224F6FE8),
  success: Color(0xFF10A372),
  error: Color(0xFFE0445C),
  warning: Color(0xFFD08700),
  info: Color(0xFF2F6FE5),
  // Syntax tones tuned for dark text on light bg — slightly desaturated so a
  // long query doesn't feel like a stained-glass window.
  sqlKeyword: Color(0xFF3A5BD9),
  sqlString: Color(0xFF1F7A4D),
  sqlNumber: Color(0xFFB04A12),
  sqlComment: Color(0xFF8A8F99),
  sqlFunction: Color(0xFF7A3FB0),
  sqlIdentifier: Color(0xFF15171C),
);

/// Runtime-mutable palette pointer. Call [setPalette] before the root
/// `MaterialApp` rebuilds; descendants will pick up the new colors as they
/// re-paint.
class AppColors {
  const AppColors._();

  static Palette _palette = darkPalette;

  static Palette get palette => _palette;
  static AppBrightness get brightness => _palette.brightness;

  static void setPalette(Palette p) {
    _palette = p;
  }

  static Color get bg => _palette.bg;
  static Color get surface => _palette.surface;
  static Color get surfaceAlt => _palette.surfaceAlt;
  static Color get surfaceHover => _palette.surfaceHover;

  static Color get sidebarTint => _palette.sidebarTint;
  static Color get sidebarRowHover => _palette.sidebarRowHover;
  static Color get sidebarRowActive => _palette.sidebarRowActive;

  static Color get border => _palette.border;
  static Color get borderStrong => _palette.borderStrong;

  static Color get textPrimary => _palette.textPrimary;
  static Color get textSecondary => _palette.textSecondary;
  static Color get textMuted => _palette.textMuted;

  static Color get accent => _palette.accent;
  static Color get accentHover => _palette.accentHover;
  static Color get accentSoft => _palette.accentSoft;

  static Color get success => _palette.success;
  static Color get error => _palette.error;
  static Color get warning => _palette.warning;
  static Color get info => _palette.info;

  static Color get sqlKeyword => _palette.sqlKeyword;
  static Color get sqlString => _palette.sqlString;
  static Color get sqlNumber => _palette.sqlNumber;
  static Color get sqlComment => _palette.sqlComment;
  static Color get sqlFunction => _palette.sqlFunction;
  static Color get sqlIdentifier => _palette.sqlIdentifier;
}

class Insets {
  const Insets._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

class Radii {
  const Radii._();

  static const Radius xs = Radius.circular(4);
  static const Radius sm = Radius.circular(6);
  static const Radius md = Radius.circular(8);
  static const Radius lg = Radius.circular(12);

  static const BorderRadius brSm = BorderRadius.all(sm);
  static const BorderRadius brMd = BorderRadius.all(md);
  static const BorderRadius brLg = BorderRadius.all(lg);
}

class AppTheme {
  const AppTheme._();

  static ThemeData build(AppBrightness brightness) {
    final base = brightness == AppBrightness.dark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);

    final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: AppColors.bg,
      textTheme: textTheme,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.accent,
        secondary: AppColors.accent,
        surface: AppColors.surface,
        error: AppColors.error,
        onSurface: AppColors.textPrimary,
      ),
      dividerColor: AppColors.border,
      iconTheme: IconThemeData(color: AppColors.textSecondary, size: 16),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: Radii.brSm,
          border: Border.all(color: AppColors.borderStrong),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        textStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 11.5,
        ),
        waitDuration: const Duration(milliseconds: 400),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(AppColors.borderStrong),
        thickness: WidgetStateProperty.all(8),
        radius: const Radius.circular(4),
      ),
    );
  }

  /// Mono style for SQL, identifiers, data cells, code blocks.
  static TextStyle mono({
    double size = 12.5,
    Color? color,
    FontWeight weight = FontWeight.w400,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: size,
      color: color ?? AppColors.textPrimary,
      fontWeight: weight,
      height: 1.4,
    );
  }

  /// UI text — Inter, with the tracking/weight tuned for compact density.
  static TextStyle ui({
    double size = 12.5,
    Color? color,
    FontWeight weight = FontWeight.w500,
    double letterSpacing = 0,
  }) {
    return GoogleFonts.inter(
      fontSize: size,
      color: color ?? AppColors.textPrimary,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      height: 1.35,
    );
  }

  /// Tiny uppercase eyebrow for section headers.
  static TextStyle eyebrow({Color? color}) {
    return GoogleFonts.inter(
      fontSize: 10.5,
      color: color ?? AppColors.textMuted,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.2,
    );
  }
}
