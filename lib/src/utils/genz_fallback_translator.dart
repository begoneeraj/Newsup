/// Lightweight, offline word-substitution fallback for [FactCheck.genzSummary].
///
/// `genz_summary` is normally written by the Groq ingestion pipeline (see
/// `src/ai_processor/groq_processor.py`) for every fact check going forward.
/// This only covers the gap: rows ingested before that prompt existed, or a
/// request that ever has to run fully offline. It is intentionally simple —
/// word substitution, not sentence rewriting — so it can never contradict
/// the verdict the way a wittier rewrite might.
library;

const Map<String, String> _replacements = {
  'false': 'cap',
  'fake': 'cap',
  'hoax': 'cap',
  'lie': 'cap',
  'lies': 'cap',
  'suspicious': 'sus',
  'questionable': 'sus',
  'sketchy': 'sus',
  'proven': 'caught in 4K',
  'confirmed': 'no cap, confirmed',
  'verified': 'no cap, verified',
  'unverified': "jury's still out on",
  'amazing': 'slaps',
  'excellent': 'bussin',
  'failed': 'cooked',
  'mediocre': 'mid',
  'unremarkable': 'mid',
  'crazy': 'wild',
  'insane': 'wild',
  'unbelievable': 'wild',
  'really': 'fr',
  'truly': 'fr',
  'honestly': 'fr',
  'absolutely not': 'nahhh',
  'somewhat': 'lowkey',
  'obviously': 'highkey',
  'clearly': 'highkey',
};

/// One emoji per output, first matching keyword wins.
const Map<String, String> _emojiByKeyword = {
  'cap': '🧢',
  'sus': '🤨',
  'no cap': '✅',
  'slaps': '🔥',
  'bussin': '🔥',
  'cooked': '💀',
  'wild': '😭',
};

/// Substitutes formal words for Gen Z slang, word-boundary safe, and
/// appends a single contextual emoji. Falls back to the original text
/// unchanged (no emoji) if nothing in the dictionary matches.
String genzFallbackTranslate(String text) {
  var matched = false;
  String? emoji;
  var result = text;
  for (final entry in _replacements.entries) {
    final pattern = RegExp(r'\b' + RegExp.escape(entry.key) + r'\b', caseSensitive: false);
    if (pattern.hasMatch(result)) {
      result = result.replaceAll(pattern, entry.value);
      matched = true;
    }
  }

  if (!matched) return text;

  for (final entry in _emojiByKeyword.entries) {
    if (result.toLowerCase().contains(entry.key)) {
      emoji = entry.value;
      break;
    }
  }

  return emoji == null ? result : '$result $emoji';
}
