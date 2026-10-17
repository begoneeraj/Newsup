import 'package:flutter/material.dart';
import 'package:newsup/src/theme/app_theme_data.dart';
import 'package:newsup/src/theme/app_voice.dart';

/// Use local system glyphs in UI tests; fonts are not the network dependency
/// under test. Product colors and layout still come from the real screens.
class TestTheme extends AppThemeData {
  TestTheme()
      : super(
            voice: AppVoice.normal,
            brightness: Brightness.light,
            bg: Colors.white,
            surface: Colors.white,
            surfaceVariant: Colors.grey,
            border: Colors.grey,
            textPrimary: Colors.black,
            textMuted: Colors.grey,
            textDisabled: Colors.grey,
            accent: Colors.blue,
            success: Colors.green,
            warning: Colors.orange,
            error: Colors.red,
            statusColors: {
              for (final status in normalLight.statusColors.keys)
                status: Colors.blue,
            },
            displayFontFamily: '',
            bodyFontFamily: '',
            monoFontFamily: '');
  @override
  TextStyle displayFont(
          {double? fontSize, FontWeight? fontWeight, Color? color}) =>
      TextStyle(fontSize: fontSize, fontWeight: fontWeight, color: color);
  @override
  TextStyle bodyFont(
          {double? fontSize, FontWeight? fontWeight, Color? color}) =>
      TextStyle(fontSize: fontSize, fontWeight: fontWeight, color: color);
  @override
  TextStyle monoFont(
          {double? fontSize, FontWeight? fontWeight, Color? color}) =>
      TextStyle(fontSize: fontSize, fontWeight: fontWeight, color: color);
}
