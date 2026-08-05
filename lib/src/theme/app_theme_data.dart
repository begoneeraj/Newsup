import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/crisis_report.dart';
import '../models/fact_check.dart';
import '../models/govt_promise.dart';
import '../models/public_event.dart';
import '../models/slow_crisis.dart';
import 'app_voice.dart';

/// Status colors are deliberately identical across voice modes — only
/// brightness darkens them by ~15%. Changing "verified" green between
/// voices would be confusing, so only accent + type personality vary.
///
/// misleading/partlyTrue/outOfContext share the design system's dedicated
/// "misleading" purple — deliberately distinct from both false-red and
/// unverified-amber so all three read as different verdicts at a glance.
const Map<FactCheckStatus, Color> _darkStatusColors = {
  FactCheckStatus.verified: Color(0xFF2ECC71),
  FactCheckStatus.falseClaim: Color(0xFFFF4757),
  FactCheckStatus.misleading: Color(0xFFA78BFA),
  FactCheckStatus.partlyTrue: Color(0xFFA78BFA),
  FactCheckStatus.outOfContext: Color(0xFFA78BFA),
  FactCheckStatus.satire: Color(0xFF6B7280),
  FactCheckStatus.unverified: Color(0xFFF5A623),
};

/// Same hues as [_darkStatusColors], darkened for contrast on light backgrounds.
const Map<FactCheckStatus, Color> _lightStatusColors = {
  FactCheckStatus.verified: Color(0xFF1E9E43),
  FactCheckStatus.falseClaim: Color(0xFFD6413F),
  FactCheckStatus.misleading: Color(0xFF8266E0),
  FactCheckStatus.partlyTrue: Color(0xFF8266E0),
  FactCheckStatus.outOfContext: Color(0xFF8266E0),
  FactCheckStatus.satire: Color(0xFF5B6270),
  FactCheckStatus.unverified: Color(0xFFA6790A),
};

/// Fixed section-identity colors — consistent across voice/brightness,
/// used wherever a screen's *section* (not a per-item verdict) needs a
/// color: the bottom nav, section headers, category chips.
class AppSectionColors {
  const AppSectionColors._();

  static const home = Color(0xFF4A9EFF);
  static const crisis = Color(0xFFFF6B4A);
  static const slowCrisis = Color(0xFFFF8C42);
  static const underreported = Color(0xFF00D2FF);
  static const govtPromises = Color(0xFFF5A623);
}

/// A full set of design tokens for one (voice, brightness) combination.
class AppThemeData {
  final AppVoice voice;
  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color surfaceVariant;
  final Color border;
  final Color textPrimary;
  final Color textMuted;
  final Color textDisabled;
  final Color accent;
  final Color success;
  final Color warning;
  final Color error;
  final Map<FactCheckStatus, Color> statusColors;
  final String displayFontFamily;
  final String bodyFontFamily;
  final String monoFontFamily;

  const AppThemeData({
    required this.voice,
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surfaceVariant,
    required this.border,
    required this.textPrimary,
    required this.textMuted,
    required this.textDisabled,
    required this.accent,
    required this.success,
    required this.warning,
    required this.error,
    required this.statusColors,
    required this.displayFontFamily,
    required this.bodyFontFamily,
    required this.monoFontFamily,
  });

  bool get isGenz => voice == AppVoice.genz;

  Color statusColor(FactCheckStatus status) => statusColors[status]!;

  /// Crisis severity reuses the same verdict hues: unresolved reads as
  /// urgent/false-red, partially-resolved as amber caution, resolved as
  /// verified-green — one accent vocabulary across both screens.
  Color crisisStatusColor(CrisisStatus status) {
    switch (status) {
      case CrisisStatus.unresolved:
        return statusColors[FactCheckStatus.falseClaim]!;
      case CrisisStatus.partiallyResolved:
        return statusColors[FactCheckStatus.misleading]!;
      case CrisisStatus.resolved:
        return statusColors[FactCheckStatus.verified]!;
    }
  }

  /// Same verdict-hue vocabulary as crisisStatusColor: high=urgent-red,
  /// medium=amber, low=verified-green. Null (no severity assigned yet, e.g.
  /// a plain fact_check-sourced public event) falls back to textMuted.
  Color publicEventSeverityColor(PublicEventSeverity? severity) {
    switch (severity) {
      case PublicEventSeverity.high:
        return statusColors[FactCheckStatus.falseClaim]!;
      case PublicEventSeverity.medium:
        return statusColors[FactCheckStatus.misleading]!;
      case PublicEventSeverity.low:
        return statusColors[FactCheckStatus.verified]!;
      case null:
        return textMuted;
    }
  }

  /// Same verdict-hue vocabulary as the other status colors above:
  /// fullyImplemented=verified-green, partiallyImplemented=amber,
  /// poorQualityImplementation=urgent-red. notStarted/onPaperOnly/null
  /// (not yet re-verified) fall back to textMuted — grey deliberately
  /// reads as "no independent verdict yet", not good or bad.
  Color implementationQualityColor(GovtPromiseImplementationQuality? quality) {
    switch (quality) {
      case GovtPromiseImplementationQuality.fullyImplemented:
        return statusColors[FactCheckStatus.verified]!;
      case GovtPromiseImplementationQuality.partiallyImplemented:
        return statusColors[FactCheckStatus.misleading]!;
      case GovtPromiseImplementationQuality.poorQualityImplementation:
        return statusColors[FactCheckStatus.falseClaim]!;
      case GovtPromiseImplementationQuality.notStarted:
      case GovtPromiseImplementationQuality.onPaperOnly:
      case null:
        return textMuted;
    }
  }

  /// supportsDone reads as verified-green, contradictsDone as urgent-red;
  /// neutralUpdate (most Q&A/CAG excerpts that don't clearly cut either
  /// way) stays textMuted rather than forcing a verdict color onto it.
  Color promiseEvidenceStanceColor(PromiseEvidenceStance stance) {
    switch (stance) {
      case PromiseEvidenceStance.supportsDone:
        return statusColors[FactCheckStatus.verified]!;
      case PromiseEvidenceStance.contradictsDone:
        return statusColors[FactCheckStatus.falseClaim]!;
      case PromiseEvidenceStance.neutralUpdate:
        return textMuted;
    }
  }

  /// critical=urgent-red, worsening=amber, improving=verified-green, same
  /// verdict-hue vocabulary as the other status colors above. stable and
  /// null (not yet computed) both fall back to textMuted - "nothing has
  /// changed" reads the same as "no verdict yet", neither is good or bad.
  Color slowCrisisSeverityColor(SlowCrisisSeverity? severity) {
    switch (severity) {
      case SlowCrisisSeverity.critical:
        return statusColors[FactCheckStatus.falseClaim]!;
      case SlowCrisisSeverity.worsening:
        return statusColors[FactCheckStatus.misleading]!;
      case SlowCrisisSeverity.improving:
        return statusColors[FactCheckStatus.verified]!;
      case SlowCrisisSeverity.stable:
      case null:
        return textMuted;
    }
  }

  /// gap_score is log2((niche+1)/(mainstream+1)) (see
  /// pipeline.underreported_topics._compute_gap_score) -- unbounded, not a
  /// 0-1 value. 0 means niche and mainstream coverage are roughly equal;
  /// +1 means niche coverage is ~2x mainstream (moderate gap); +2 means ~4x
  /// (severe gap). Buckets into the same three-tier palette
  /// slowCrisisSeverityColor uses rather than adding a fourth status color.
  Color gapScoreColor(double? gapScore) {
    if (gapScore == null) return textMuted;
    if (gapScore >= 2) return statusColors[FactCheckStatus.falseClaim]!;
    if (gapScore >= 1) return statusColors[FactCheckStatus.misleading]!;
    return statusColors[FactCheckStatus.verified]!;
  }

  /// Presentation-only bucketing of a 0-100 confidence score into a short
  /// human label, paired with the numeric value in the redesigned
  /// confidence indicator (e.g. "High Confidence · 97%").
  String confidenceLabel(double confidence) {
    if (confidence >= 90) return 'High Confidence';
    if (confidence >= 70) return 'Moderate Confidence';
    if (confidence >= 40) return 'Low Confidence';
    return 'Very Low Confidence';
  }

  TextStyle displayFont(
          {double? fontSize, FontWeight? fontWeight, Color? color}) =>
      GoogleFonts.getFont(
        displayFontFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color ?? textPrimary,
      );

  TextStyle bodyFont(
          {double? fontSize, FontWeight? fontWeight, Color? color}) =>
      GoogleFonts.getFont(
        bodyFontFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color ?? textPrimary,
      );

  TextStyle monoFont(
          {double? fontSize, FontWeight? fontWeight, Color? color}) =>
      GoogleFonts.getFont(
        monoFontFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color ?? textPrimary,
      );

  ThemeData toThemeData() {
    final base = GoogleFonts.getTextTheme(
      bodyFontFamily,
      brightness == Brightness.dark
          ? Typography.whiteMountainView
          : Typography.blackMountainView,
    );

    final textTheme = base.copyWith(
      displayLarge: GoogleFonts.getFont(displayFontFamily,
          color: textPrimary, fontWeight: FontWeight.w700, fontSize: 24),
      displayMedium: GoogleFonts.getFont(displayFontFamily,
          color: textPrimary, fontWeight: FontWeight.w700, fontSize: 22),
      titleLarge: GoogleFonts.getFont(displayFontFamily,
          color: textPrimary, fontWeight: FontWeight.w700, fontSize: 22),
      titleMedium: GoogleFonts.getFont(displayFontFamily,
          color: textPrimary, fontWeight: FontWeight.w600, fontSize: 18),
      titleSmall: GoogleFonts.getFont(bodyFontFamily,
          color: textPrimary, fontWeight: FontWeight.w600, fontSize: 17),
      bodyLarge: GoogleFonts.getFont(bodyFontFamily,
          color: textPrimary, fontSize: 15),
      bodyMedium: GoogleFonts.getFont(bodyFontFamily,
          color: textPrimary, fontSize: 15),
      bodySmall: GoogleFonts.getFont(bodyFontFamily,
          color: textMuted, fontSize: 13),
      labelSmall: GoogleFonts.getFont(bodyFontFamily,
          color: textMuted, fontSize: 12),
    );

    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      surface: surface,
    ).copyWith(
      primary: accent,
      secondary: accent,
      surfaceContainerHighest: surfaceVariant,
      error: error,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      splashFactory: InkSparkle.splashFactory,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.getFont(
          displayFontFamily,
          color: textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 22,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, space: 1),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: accent.withValues(alpha: 0.18),
        indicatorShape: const StadiumBorder(),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.getFont(
            bodyFontFamily,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? accent : textMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? accent : textMuted);
        }),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: textMuted,
        indicatorColor: accent,
        dividerColor: border,
        labelStyle: GoogleFonts.getFont(bodyFontFamily,
            fontWeight: FontWeight.w600, fontSize: 13),
        unselectedLabelStyle: GoogleFonts.getFont(bodyFontFamily,
            fontWeight: FontWeight.w500, fontSize: 13),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceVariant,
        side: BorderSide.none,
        labelStyle: GoogleFonts.getFont(bodyFontFamily,
            color: textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
        shape: const StadiumBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceVariant,
        hintStyle: GoogleFonts.getFont(bodyFontFamily, color: textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.transparent, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.transparent, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),
      iconTheme: IconThemeData(color: textMuted),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
    );
  }
}

const normalDark = AppThemeData(
  voice: AppVoice.normal,
  brightness: Brightness.dark,
  bg: Color(0xFF0A0E14),
  surface: Color(0xFF12161F),
  surfaceVariant: Color(0xFF1A1F2B),
  border: Color(0xFF232A38),
  textPrimary: Color(0xFFF2F4F8),
  textMuted: Color(0xFF8892A6),
  textDisabled: Color(0xFF4A5468),
  accent: Color(0xFF4A9EFF),
  success: Color(0xFF2ECC71),
  warning: Color(0xFFF5A623),
  error: Color(0xFFFF4757),
  statusColors: _darkStatusColors,
  displayFontFamily: 'IBM Plex Sans',
  bodyFontFamily: 'IBM Plex Sans',
  monoFontFamily: 'IBM Plex Mono',
);

const normalLight = AppThemeData(
  voice: AppVoice.normal,
  brightness: Brightness.light,
  bg: Color(0xFFF6F7FA),
  surface: Color(0xFFFFFFFF),
  surfaceVariant: Color(0xFFEDF0F6),
  border: Color(0xFFE1E4EC),
  textPrimary: Color(0xFF12151C),
  textMuted: Color(0xFF5B6270),
  textDisabled: Color(0xFFA6AEBD),
  accent: Color(0xFF3A6FE0),
  success: Color(0xFF1E9E43),
  warning: Color(0xFFA6790A),
  error: Color(0xFFD6413F),
  statusColors: _lightStatusColors,
  displayFontFamily: 'IBM Plex Sans',
  bodyFontFamily: 'IBM Plex Sans',
  monoFontFamily: 'IBM Plex Mono',
);

const genzDark = AppThemeData(
  voice: AppVoice.genz,
  brightness: Brightness.dark,
  bg: Color(0xFF0A0E14),
  surface: Color(0xFF12161F),
  surfaceVariant: Color(0xFF1A1F2B),
  border: Color(0xFF232A38),
  textPrimary: Color(0xFFF2F4F8),
  textMuted: Color(0xFF8892A6),
  textDisabled: Color(0xFF4A5468),
  accent: Color(0xFFFF5470),
  success: Color(0xFF2ECC71),
  warning: Color(0xFFF5A623),
  error: Color(0xFFFF4757),
  statusColors: _darkStatusColors,
  displayFontFamily: 'Space Grotesk',
  bodyFontFamily: 'IBM Plex Sans',
  monoFontFamily: 'IBM Plex Mono',
);

const genzLight = AppThemeData(
  voice: AppVoice.genz,
  brightness: Brightness.light,
  bg: Color(0xFFF6F7FA),
  surface: Color(0xFFFFFFFF),
  surfaceVariant: Color(0xFFEDF0F6),
  border: Color(0xFFE1E4EC),
  textPrimary: Color(0xFF12151C),
  textMuted: Color(0xFF5B6270),
  textDisabled: Color(0xFFA6AEBD),
  accent: Color(0xFFD6294B),
  success: Color(0xFF1E9E43),
  warning: Color(0xFFA6790A),
  error: Color(0xFFD6413F),
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
