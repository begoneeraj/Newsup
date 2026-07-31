/// App-wide security policy constants and helpers.
///
/// Supabase URL and publishable key must always come from
/// `--dart-define=SUPABASE_URL=...` / `--dart-define=SUPABASE_PUBLISHABLE_KEY=...`
/// (see `main.dart`) or a remote-config service fetched at runtime — never
/// hardcode either value as a literal, in this file or anywhere else.
library;

import 'package:flutter/foundation.dart';

/// Flip to `true` locally when you need verbose debug output. Never commit
/// this as `true` — and even if it slips through, [secureLog] still no-ops
/// outside debug builds, so a stray `true` can't leak logs into a release.
const bool kDebugLogging = false;

/// Debug-only logging. No-ops unless both [kDebugLogging] is on AND the
/// binary is an actual debug build (`kDebugMode`) — this second check is
/// what keeps verbose logs out of release builds regardless of what
/// [kDebugLogging] is set to.
void secureLog(String message) {
  if (kDebugLogging && kDebugMode) {
    debugPrint(message);
  }
}
