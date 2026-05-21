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
    required this.bgDeep,
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.surface2,
    required this.surfaceHover,
    required this.sidebarTint,
    required this.sidebarRowHover,
    required this.sidebarRowActive,
    required this.border,
    required this.borderSoft,
    required this.borderStrong,
    required this.hairline,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.text4,
    required this.accent,
    required this.accentHover,
    required this.accentSoft,
    required this.accentRing,
    required this.success,
    required this.error,
    required this.dangerSoft,
    required this.warning,
    required this.warn,
    required this.info,
    required this.tNull,
    required this.tNum,
    required this.tStr,
    required this.tBool,
    required this.tUuid,
    required this.tDate,
    required this.tJson,
    required this.tFk,
    required this.sqlKeyword,
    required this.sqlString,
    required this.sqlNumber,
    required this.sqlComment,
    required this.sqlFunction,
    required this.sqlIdentifier,
    required this.sqlOperator,
  });

  final AppBrightness brightness;

  /// Deepest background — toolbar, tab strip, grid headers, page bar.
  final Color bgDeep;
  final Color bg;
  final Color surface;

  /// Alias for surface2; kept for backward compatibility.
  final Color surfaceAlt;
  final Color surface2;
  final Color surfaceHover;

  final Color sidebarTint;
  final Color sidebarRowHover;
  final Color sidebarRowActive;

  final Color border;

  /// Softer hairline — subtler than border, used for per-tab right dividers.
  final Color borderSoft;
  final Color borderStrong;

  /// Very subtle white/black hairline for internal dividers.
  final Color hairline;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  /// Fourth text tier — dimmer than textMuted, for de-emphasised annotations.
  final Color text4;

  final Color accent;
  final Color accentHover;
  final Color accentSoft;
  final Color accentRing;

  final Color success;
  final Color error;
  final Color dangerSoft;

  /// Kept for backward compat; same as warn.
  final Color warning;
  final Color warn;
  final Color info;

  // Type colors — used to tint data cells by column type.
  final Color tNull;
  final Color tNum;
  final Color tStr;
  final Color tBool;
  final Color tUuid;
  final Color tDate;
  final Color tJson;
  final Color tFk;

  final Color sqlKeyword;
  final Color sqlString;
  final Color sqlNumber;
  final Color sqlComment;
  final Color sqlFunction;
  final Color sqlIdentifier;
  final Color sqlOperator;
}

const Palette darkPalette = Palette(
  brightness: AppBrightness.dark,
  bgDeep: Color(0xFF0A0C10),
  bg: Color(0xFF0E1014),
  surface: Color(0xFF16181C),
  surfaceAlt: Color(0xFF1A1D23),
  surface2: Color(0xFF1A1D23),
  surfaceHover: Color(0xFF1F232A),
  sidebarTint: Color(0xFF13151A),
  sidebarRowHover: Color(0x06FFFFFF),
  sidebarRowActive: Color(0x1A5B7CFA),
  border: Color(0xFF21252D),
  borderSoft: Color(0xFF1B1E25),
  borderStrong: Color(0xFF2B2F38),
  hairline: Color(0x0FFFFFFF),
  textPrimary: Color(0xFFE6E8EC),
  textSecondary: Color(0xFFB0B6C2),
  textMuted: Color(0xFF757C8A),
  text4: Color(0xFF4D5462),
  accent: Color(0xFF5B7CFA),
  accentHover: Color(0xFF6E8BFA),
  accentSoft: Color(0x245B7CFA),
  accentRing: Color(0x595B7CFA),
  success: Color(0xFF57B07A),
  error: Color(0xFFE5484D),
  dangerSoft: Color(0x1FE5484D),
  warning: Color(0xFFC9933C),
  warn: Color(0xFFC9933C),
  info: Color(0xFF60A5FA),
  tNull: Color(0xFF6B7180),
  tNum: Color(0xFFD6C68F),
  tStr: Color(0xFFBFD1E7),
  tBool: Color(0xFF93C9A3),
  tUuid: Color(0xFF8FA9CB),
  tDate: Color(0xFFC9A3D1),
  tJson: Color(0xFFD8B58B),
  tFk: Color(0xFF87A0DA),
  sqlKeyword: Color(0xFF8FA9F6),
  sqlString: Color(0xFF93C9A3),
  sqlNumber: Color(0xFFD6C68F),
  sqlComment: Color(0xFF5F6672),
  sqlFunction: Color(0xFFC9A3D1),
  sqlIdentifier: Color(0xFFE6E8EC),
  sqlOperator: Color(0xFF9097A3),
);

/// Off-white "paper" surface with the same indigo accent. Surfaces lean on
/// cool neutral grays so the palette stays in the same slate family as the
/// dark variant — no warm/sepia cast, no yellow numbers.
const Palette lightPalette = Palette(
  brightness: AppBrightness.light,
  bgDeep: Color(0xFFEDEFF3),
  bg: Color(0xFFF4F5F7),
  surface: Color(0xFFFFFFFF),
  surfaceAlt: Color(0xFFF1F2F5),
  surface2: Color(0xFFF1F2F5),
  surfaceHover: Color(0xFFE7E9ED),
  sidebarTint: Color(0xFFFAFBFC),
  sidebarRowHover: Color(0xFFEDEFF3),
  sidebarRowActive: Color(0x224F6FE8),
  border: Color(0xFFE2E4E9),
  borderSoft: Color(0xFFEAECF0),
  borderStrong: Color(0xFFCBCED5),
  hairline: Color(0x14000000),
  textPrimary: Color(0xFF15171C),
  textSecondary: Color(0xFF5A6170),
  textMuted: Color(0xFF98A0AC),
  text4: Color(0xFFBEC3CC),
  accent: Color(0xFF4F6FE8),
  accentHover: Color(0xFF3A5BD9),
  accentSoft: Color(0x224F6FE8),
  accentRing: Color(0x4F4F6FE8),
  success: Color(0xFF10A372),
  error: Color(0xFFE0445C),
  dangerSoft: Color(0x1FB0322F),
  warning: Color(0xFFB45A1F),
  warn: Color(0xFFB45A1F),
  info: Color(0xFF2F6FE5),
  tNull: Color(0xFF98A0AC),
  tNum: Color(0xFF1F4E8C),
  tStr: Color(0xFF1A1815),
  tBool: Color(0xFF2F7A4F),
  tUuid: Color(0xFF3A4A6B),
  tDate: Color(0xFF6B3A78),
  tJson: Color(0xFF7A3FB0),
  tFk: Color(0xFF2A3FAA),
  // Syntax tones tuned for dark text on light bg — slightly desaturated so a
  // long query doesn't feel like a stained-glass window.
  sqlKeyword: Color(0xFF3A5BD9),
  sqlString: Color(0xFF1F7A4D),
  sqlNumber: Color(0xFF1F4E8C),
  sqlComment: Color(0xFF8A8F99),
  sqlFunction: Color(0xFF7A3FB0),
  sqlIdentifier: Color(0xFF15171C),
  sqlOperator: Color(0xFF4F4A40),
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

  static Color get bgDeep => _palette.bgDeep;

  static Color get bg => _palette.bg;

  static Color get surface => _palette.surface;

  static Color get surfaceAlt => _palette.surfaceAlt;

  static Color get surface2 => _palette.surface2;

  static Color get surfaceHover => _palette.surfaceHover;

  static Color get sidebarTint => _palette.sidebarTint;

  static Color get sidebarRowHover => _palette.sidebarRowHover;

  static Color get sidebarRowActive => _palette.sidebarRowActive;

  static Color get border => _palette.border;

  static Color get borderSoft => _palette.borderSoft;

  static Color get borderStrong => _palette.borderStrong;

  static Color get hairline => _palette.hairline;

  static Color get textPrimary => _palette.textPrimary;

  static Color get textSecondary => _palette.textSecondary;

  static Color get textMuted => _palette.textMuted;

  static Color get text4 => _palette.text4;

  static Color get accent => _palette.accent;

  static Color get accentHover => _palette.accentHover;

  static Color get accentSoft => _palette.accentSoft;

  static Color get accentRing => _palette.accentRing;

  static Color get success => _palette.success;

  static Color get error => _palette.error;

  static Color get dangerSoft => _palette.dangerSoft;

  static Color get warning => _palette.warning;

  static Color get warn => _palette.warn;

  static Color get info => _palette.info;

  static Color get tNull => _palette.tNull;

  static Color get tNum => _palette.tNum;

  static Color get tStr => _palette.tStr;

  static Color get tBool => _palette.tBool;

  static Color get tUuid => _palette.tUuid;

  static Color get tDate => _palette.tDate;

  static Color get tJson => _palette.tJson;

  static Color get tFk => _palette.tFk;

  static Color get sqlKeyword => _palette.sqlKeyword;

  static Color get sqlString => _palette.sqlString;

  static Color get sqlNumber => _palette.sqlNumber;

  static Color get sqlComment => _palette.sqlComment;

  static Color get sqlFunction => _palette.sqlFunction;

  static Color get sqlIdentifier => _palette.sqlIdentifier;

  static Color get sqlOperator => _palette.sqlOperator;
}

class AppLayout {
  const AppLayout._();

  static const double toolbarHeight = 36.0;
  static const double tabHeight = 32.0;
  static const double gridRowHeight = 26.0;
  static const double treeRowHeight = 22.0;
  static const double gridHeaderHeight = 28.0;
  static const double pageBarHeight = 28.0;
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
        textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 11.5),
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
    double letterSpacing = -0.3,
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
      fontSize: 10,
      color: color ?? AppColors.textMuted,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
    );
  }
}
