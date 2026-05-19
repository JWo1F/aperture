import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// "Aperture" — Linear-style restraint with macOS-native translucency.
///
/// One saturated indigo accent, near-black panels, hairline borders, and a
/// translucent sidebar that lets the desktop show through. Avoids both the
/// previous amber-on-ink direction and the generic JetBrains gray.
class AppColors {
  const AppColors._();

  // Window / panel
  static const Color bg = Color(0xFF0E1014);          // workspace background
  static const Color surface = Color(0xFF16181C);     // toolbars, dialogs
  static const Color surfaceAlt = Color(0xFF1B1E23);  // grid alt rows, chips
  static const Color surfaceHover = Color(0xFF22262C);

  // Sidebar — opaque dark panel; the macOS material blur underneath was
  // washing out the text on light desktop backgrounds.
  static const Color sidebarTint = Color(0xFF13151A);
  static const Color sidebarRowHover = Color(0xFF1D2027);
  static const Color sidebarRowActive = Color(0x335B7CFA);

  static const Color border = Color(0xFF24272D);
  static const Color borderStrong = Color(0xFF2F333B);

  static const Color textPrimary = Color(0xFFE9EAEC);
  static const Color textSecondary = Color(0xFF9BA1AB);
  static const Color textMuted = Color(0xFF5C636E);

  // Indigo accent — sole brand colour
  static const Color accent = Color(0xFF5B7CFA);
  static const Color accentHover = Color(0xFF7D97FF);
  static const Color accentSoft = Color(0x335B7CFA);

  static const Color success = Color(0xFF34D399);
  static const Color error = Color(0xFFFB7185);
  static const Color warning = Color(0xFFFBBF24);
  static const Color info = Color(0xFF60A5FA);

  // Syntax tokens (Aperture-tuned, not Darcula clone)
  static const Color sqlKeyword = Color(0xFF93B4FF);
  static const Color sqlString = Color(0xFFA3E1B0);
  static const Color sqlNumber = Color(0xFFE8B583);
  static const Color sqlComment = Color(0xFF5C636E);
  static const Color sqlFunction = Color(0xFFC4A7FF);
  static const Color sqlIdentifier = Color(0xFFE9EAEC);
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

  static ThemeData build() {
    final base = ThemeData.dark(useMaterial3: true);
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
      iconTheme: const IconThemeData(color: AppColors.textSecondary, size: 16),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: Radii.brSm,
          border: Border.all(color: AppColors.borderStrong),
          boxShadow: const [
            BoxShadow(color: Color(0x55000000), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        textStyle: const TextStyle(
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
    Color color = AppColors.textPrimary,
    FontWeight weight = FontWeight.w400,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: size,
      color: color,
      fontWeight: weight,
      height: 1.4,
    );
  }

  /// UI text — Inter, with the tracking/weight tuned for compact density.
  static TextStyle ui({
    double size = 12.5,
    Color color = AppColors.textPrimary,
    FontWeight weight = FontWeight.w500,
    double letterSpacing = 0,
  }) {
    return GoogleFonts.inter(
      fontSize: size,
      color: color,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      height: 1.35,
    );
  }

  /// Tiny uppercase eyebrow for section headers.
  static TextStyle eyebrow({Color color = AppColors.textMuted}) {
    return GoogleFonts.inter(
      fontSize: 10.5,
      color: color,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.2,
    );
  }
}
