import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme_providers.dart';

/// Colored initial avatar standing in for a source favicon — the origin
/// string ("google_news", a subreddit, a handle) rarely has an image, but a
/// consistent monogram still reads as "this came from somewhere specific"
/// rather than plain gray metadata text.
class SourceMonogram extends ConsumerWidget {
  const SourceMonogram({super.key, required this.origin, this.size = 22});

  final String origin;
  final double size;

  static const _palette = [
    Color(0xFF4A8FCC),
    Color(0xFFC98A3D),
    Color(0xFF6E6ADB),
    Color(0xFF4C9A5D),
    Color(0xFFC4534A),
    Color(0xFF3DA6A6),
  ];

  String get _initial {
    final trimmed = origin.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed[0].toUpperCase();
  }

  Color get _color => _palette[origin.hashCode.abs() % _palette.length];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _color.withValues(alpha: 0.22),
        border: Border.all(color: _color.withValues(alpha: 0.5), width: 1),
      ),
      child: Text(
        _initial,
        style: theme.bodyFont(fontSize: size * 0.42, fontWeight: FontWeight.w700, color: _color),
      ),
    );
  }
}
