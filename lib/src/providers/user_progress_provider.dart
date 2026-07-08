import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme_providers.dart';

const _xpKey = 'newsup.realityFeed.xp';
const _streakKey = 'newsup.realityFeed.streakDays';
const _lastActiveKey = 'newsup.realityFeed.lastActiveDate';
const _correctKey = 'newsup.realityFeed.correctGuesses';
const _gradedKey = 'newsup.realityFeed.gradedGuesses';

class UserProgress {
  final int xp;
  final int streakDays;
  final int correctGuesses;
  final int gradedGuesses;

  const UserProgress({
    required this.xp,
    required this.streakDays,
    required this.correctGuesses,
    required this.gradedGuesses,
  });

  int get accuracyPercent =>
      gradedGuesses == 0 ? 0 : ((correctGuesses / gradedGuesses) * 100).round();

  String get rank {
    if (xp >= 2000) return 'News Wizard';
    if (xp >= 1000) return 'Truth Goblin';
    if (xp >= 500) return 'Cap Hunter';
    if (xp >= 150) return 'Fact Detective';
    return 'Reality Rookie';
  }

  UserProgress copyWith({int? xp, int? streakDays, int? correctGuesses, int? gradedGuesses}) {
    return UserProgress(
      xp: xp ?? this.xp,
      streakDays: streakDays ?? this.streakDays,
      correctGuesses: correctGuesses ?? this.correctGuesses,
      gradedGuesses: gradedGuesses ?? this.gradedGuesses,
    );
  }
}

/// Result of a single swipe guess, fed into [UserProgressNotifier.recordGuess].
enum GuessOutcome { correct, wrong, ungraded }

class UserProgressNotifier extends StateNotifier<UserProgress> {
  UserProgressNotifier(this._ref) : super(_load(_ref)) {
    _bumpStreakIfNewDay();
  }

  final Ref _ref;

  static UserProgress _load(Ref ref) {
    final prefs = ref.read(sharedPreferencesProvider);
    return UserProgress(
      xp: prefs.getInt(_xpKey) ?? 0,
      streakDays: prefs.getInt(_streakKey) ?? 0,
      correctGuesses: prefs.getInt(_correctKey) ?? 0,
      gradedGuesses: prefs.getInt(_gradedKey) ?? 0,
    );
  }

  void _bumpStreakIfNewDay() {
    final prefs = _ref.read(sharedPreferencesProvider);
    final today = _dateKey(DateTime.now());
    final lastActive = prefs.getString(_lastActiveKey);
    if (lastActive == today) return;

    final isConsecutiveDay = lastActive != null &&
        _dateKey(DateTime.now().subtract(const Duration(days: 1))) == lastActive;
    final nextStreak = isConsecutiveDay ? state.streakDays + 1 : 1;

    state = state.copyWith(streakDays: nextStreak);
    prefs.setString(_lastActiveKey, today);
    prefs.setInt(_streakKey, nextStreak);
  }

  static String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  /// Awards XP for a swipe guess and updates rolling accuracy.
  /// Returns the XP delta actually awarded (0 for ungraded/wrong).
  int recordGuess(GuessOutcome outcome) {
    final prefs = _ref.read(sharedPreferencesProvider);
    if (outcome == GuessOutcome.ungraded) return 0;

    final correct = outcome == GuessOutcome.correct;
    final xpDelta = correct ? 15 : 3;

    state = state.copyWith(
      xp: state.xp + xpDelta,
      gradedGuesses: state.gradedGuesses + 1,
      correctGuesses: state.correctGuesses + (correct ? 1 : 0),
    );
    prefs.setInt(_xpKey, state.xp);
    prefs.setInt(_gradedKey, state.gradedGuesses);
    prefs.setInt(_correctKey, state.correctGuesses);
    return xpDelta;
  }
}

final userProgressProvider = StateNotifierProvider<UserProgressNotifier, UserProgress>((ref) {
  return UserProgressNotifier(ref);
});
