import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/fact_check.dart';
import 'app_voice.dart';

/// Status colors are deliberately identical across voice modes — only
/// brightness darkens them by ~15%. Changing "verified" green between
/// voices would be confusing, so only accent + type personality vary.
const Map<FactCheckStatus, Color> _darkStatusColors = {
  FactCheckStatus.verified: Color(0xFF4C9A5D),
  FactCheckStatus.falseClaim: Color(0xFFC4534A),
  FactCheckStatus.misleading: Color(0xFFC98A3D),
  FactCheckStatus.partlyTrue: Color(0xFFC98A3D),
  FactCheckStatus.outOfContext: Color(0xFFC98A3D),
  FactCheckStatus.satire: Color(0xFF6E6ADB),
  FactCheckStatus.unverified: Color(0xFF6B7280),
};

/// Same hues as [_darkStatusColors], darkened ~15% for light backgrounds.
const Map<FactCheckStatus, Color> _lightStatusColors = {
  FactCheckStatus.verified: Color(0xFF41834F),
  FactCheckStatus.falseClaim: Color(0xFFA7473F),
  FactCheckStatus.misleading: Color(0xFFAB7534),
  FactCheckStatus.partlyTrue: Color(0xFFAB7534),
  FactCheckStatus.outOfContext: Color(0xFFAB7534),
  FactCheckStatus.satire: Color(0xFF5E5ABA),
  FactCheckStatus.unverified: Color(0xFF5B616D),
};

/// A full set of design tokens for one (voice, brightness) combination.
class AppThemeData {
  final AppVoice voice;
  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color border;
  final Color textPrimary;
  final Color textMuted;
  final Color accent;
  final Map<FactCheckStatus, Color> statusColors;
  final String displayFontFamily;
  final String bodyFontFamily;
  final String monoFontFamily;

  const AppThemeData({
    required this.voice,
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.border,
    required this.textPrimary,
    required this.textMuted,
    required this.accent,
    required this.statusColors,
    required this.displayFontFamily,
    required this.bodyFontFamily,
    required this.monoFontFamily,
  });

  bool get isGenz => voice == AppVoice.genz;

  Color statusColor(FactCheckStatus status) => statusColors[status]!;

  TextStyle displayFont({double? fontSize, FontWeight? fontWeight, Color? color}) =>
      GoogleFonts.getFont(
        displayFontFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color ?? textPrimary,
      );

  TextStyle bodyFont({double? fontSize, FontWeight? fontWeight, Color? color}) =>
      GoogleFonts.getFont(
        bodyFontFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color ?? textPrimary,
      );

  TextStyle monoFont({double? fontSize, FontWeight? fontWeight, Color? color}) =>
      GoogleFonts.getFont(
        monoFontFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color ?? textPrimary,
      );

  ThemeData toThemeData() {
    final base = GoogleFonts.getTextTheme(
      bodyFontFamily,
      brightness == Brightness.dark ? Typography.whiteMountainView : Typography.blackMountainView,
    );

    final textTheme = base.copyWith(
      displayLarge: GoogleFonts.getFont(displayFontFamily, color: textPrimary, fontWeight: FontWeight.w700),
      displayMedium: GoogleFonts.getFont(displayFontFamily, color: textPrimary, fontWeight: FontWeight.w700),
      titleLarge: GoogleFonts.getFont(displayFontFamily, color: textPrimary, fontWeight: FontWeight.w700),
      titleMedium: GoogleFonts.getFont(displayFontFamily, color: textPrimary, fontWeight: FontWeight.w600),
      titleSmall: GoogleFonts.getFont(bodyFontFamily, color: textPrimary, fontWeight: FontWeight.w600),
      bodyLarge: GoogleFonts.getFont(bodyFontFamily, color: textPrimary),
      bodyMedium: GoogleFonts.getFont(bodyFontFamily, color: textPrimary),
      bodySmall: GoogleFonts.getFont(bodyFontFamily, color: textMuted),
      labelSmall: GoogleFonts.getFont(bodyFontFamily, color: textMuted),
    );

    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      surface: surface,
    ).copyWith(primary: accent, secondary: accent);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.getFont(
          displayFontFamily,
          color: textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 20,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: border),
        ),
      ),
      dividerTheme: DividerThemeData(color: border),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bg,
        indicatorColor: accent.withValues(alpha: 0.35),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: textMuted,
        indicatorColor: accent,
        dividerColor: border,
        labelStyle: GoogleFonts.getFont(bodyFontFamily, fontWeight: FontWeight.w600, fontSize: 13),
        unselectedLabelStyle: GoogleFonts.getFont(bodyFontFamily, fontWeight: FontWeight.w500, fontSize: 13),
      ),
    );
  }
}

final normalDark = AppThemeData(
  voice: AppVoice.normal,
  brightness: Brightness.dark,
  bg: const Color(0xFF14171C),
  surface: const Color(0xFF1C2028),
  border: const Color(0xFF2A2F38),
  textPrimary: const Color(0xFFEDEFF2),
  textMuted: const Color(0xFF8B93A1),
  accent: const Color(0xFF3F7CAC),
  statusColors: _darkStatusColors,
  displayFontFamily: 'IBM Plex Sans',
  bodyFontFamily: 'IBM Plex Sans',
  monoFontFamily: 'IBM Plex Mono',
);

final normalLight = AppThemeData(
  voice: AppVoice.normal,
  brightness: Brightness.light,
  bg: const Color(0xFFF5F6F4),
  surface: const Color(0xFFFFFFFF),
  border: const Color(0xFFE1E3E0),
  textPrimary: const Color(0xFF14171C),
  textMuted: const Color(0xFF5B6270),
  accent: const Color(0xFF2A5F87),
  statusColors: _lightStatusColors,
  displayFontFamily: 'IBM Plex Sans',
  bodyFontFamily: 'IBM Plex Sans',
  monoFontFamily: 'IBM Plex Mono',
);

final genzDark = AppThemeData(
  voice: AppVoice.genz,
  brightness: Brightness.dark,
  bg: const Color(0xFF14171C),
  surface: const Color(0xFF1C2028),
  border: const Color(0xFF2A2F38),
  textPrimary: const Color(0xFFEDEFF2),
  textMuted: const Color(0xFF8B93A1),
  accent: const Color(0xFFFF5470),
  statusColors: _darkStatusColors,
  displayFontFamily: 'Space Grotesk',
  bodyFontFamily: 'IBM Plex Sans',
  monoFontFamily: 'IBM Plex Mono',
);

final genzLight = AppThemeData(
  voice: AppVoice.genz,
  brightness: Brightness.light,
  bg: const Color(0xFFF5F6F4),
  surface: const Color(0xFFFFFFFF),
  border: const Color(0xFFE1E3E0),
  textPrimary: const Color(0xFF14171C),
  textMuted: const Color(0xFF5B6270),
  accent: const Color(0xFFD6294B),
  statusColors: _lightStatusColors,
  displayFontFamily: 'Space Grotesk',
  bodyFontFamily: 'IBM Plex Sans',
  monoFontFamily: 'IBM Plex Mono',
);

AppThemeData resolveAppTheme(AppVoice voice, Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  switch (voice) {
    case AppVoice.normal:
      return isDark ? normalDark : normalLight;
    case AppVoice.genz:
      return isDark ? genzDark : genzLight;
  }
}
