import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme_providers.dart';

const _bookmarksKey = 'newsup.bookmarks';

/// Local-only bookmark set, keyed by a caller-chosen entity id (e.g. a
/// fact check's id). Presentation-layer feature: nothing here reaches the
/// backend, it only persists on-device via the shared_preferences instance
/// already wired up in [sharedPreferencesProvider].
class BookmarksNotifier extends StateNotifier<Set<String>> {
  BookmarksNotifier(this._ref) : super(_load(_ref));

  final Ref _ref;

  static Set<String> _load(Ref ref) {
    final stored = ref.read(sharedPreferencesProvider).getStringList(_bookmarksKey);
    return stored?.toSet() ?? <String>{};
  }

  void toggle(String id) {
    final next = {...state};
    if (!next.remove(id)) next.add(id);
    state = next;
    _ref.read(sharedPreferencesProvider).setStringList(_bookmarksKey, next.toList());
  }

  bool isBookmarked(String id) => state.contains(id);
}

final bookmarksProvider = StateNotifierProvider<BookmarksNotifier, Set<String>>(
  (ref) => BookmarksNotifier(ref),
);
