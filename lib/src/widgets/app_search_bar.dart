import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme_providers.dart';

/// Rounded, elevated search field for filtering an already-loaded list
/// client-side. Purely presentational — the caller owns the query string
/// and does its own local filtering; no network/provider calls happen here.
class AppSearchBar extends ConsumerStatefulWidget {
  const AppSearchBar({
    super.key,
    required this.hintText,
    required this.onChanged,
  });

  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  ConsumerState<AppSearchBar> createState() => _AppSearchBarState();
}

class _AppSearchBarState extends ConsumerState<AppSearchBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(appThemeDataProvider);

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: theme.surfaceVariant,
        borderRadius: BorderRadius.circular(24),
      ),
      child: TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        style: theme.bodyFont(fontSize: 15, color: theme.textPrimary),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: theme.bodyFont(fontSize: 15, color: theme.textMuted),
          prefixIcon: Icon(Icons.search_rounded, color: theme.textMuted, size: 22),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: Icon(Icons.close_rounded, color: theme.textMuted, size: 20),
                onPressed: () {
                  _controller.clear();
                  widget.onChanged('');
                },
              );
            },
          ),
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
