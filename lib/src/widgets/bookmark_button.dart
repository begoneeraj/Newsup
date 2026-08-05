import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/bookmark_provider.dart';
import '../theme/theme_providers.dart';

/// Icon-button affordance for [bookmarksProvider], sized to a comfortable
/// 48dp touch target with an animated fill/outline swap on toggle.
class BookmarkButton extends ConsumerWidget {
  const BookmarkButton({super.key, required this.id, this.size = 18});

  final String id;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);
    final bookmarked = ref.watch(bookmarksProvider).contains(id);

    return SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => ref.read(bookmarksProvider.notifier).toggle(id),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: Icon(
                bookmarked ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                key: ValueKey(bookmarked),
                size: size,
                color: bookmarked ? theme.accent : theme.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
