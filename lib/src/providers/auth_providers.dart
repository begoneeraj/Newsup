import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';

/// Firebase's own auth stream — emits once with the persisted session (or
/// `null`) on cold start, then again on every sign-in/out. [appRouterProvider]
/// watches this directly so the router redirects the moment it changes.
final authStateProvider = StreamProvider<User?>((ref) {
  return AuthService.instance.authStateChanges;
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateProvider).valueOrNull;
});
