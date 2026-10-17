import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'push_notification_service.dart';
import 'account_deletion.dart';

/// Thin wrapper around Firebase Auth + Google Sign-In. The app has exactly
/// one identity provider (Google) — every user must sign in this way, so
/// there's no separate email/password path to branch on.
class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _initialized = false;

  FirebaseAuth get _auth => FirebaseAuth.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  /// Must complete before [signInWithGoogle] or [signInSilently] are called.
  /// Safe to call more than once — `google_sign_in` requires exactly one
  /// `initialize()` call per process, so this guards against re-entry from
  /// e.g. a provider rebuilding.
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    await _googleSignIn.initialize();
    _initialized = true;
  }

  /// Attempts to restore a previous Google session without showing any UI —
  /// called once at app start so a returning user skips the login screen
  /// entirely when Firebase's own persisted session has expired but Google
  /// still remembers them.
  Future<void> signInSilently() async {
    await ensureInitialized();
    if (!_googleSignIn.supportsAuthenticate()) return;
    try {
      await _googleSignIn.attemptLightweightAuthentication();
    } catch (_) {
      // No cached session — fall through to the login screen.
    }
  }

  /// Runs the interactive Google account picker, then exchanges the
  /// resulting ID token for a Firebase session. Throws [GoogleSignInException]
  /// (e.g. the user cancels) or a [FirebaseAuthException] on failure — the
  /// login screen is responsible for turning those into user-facing text.
  Future<UserCredential> signInWithGoogle() async {
    await ensureInitialized();
    final account = await _googleSignIn.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw FirebaseAuthException(
        code: 'missing-id-token',
        message: 'Google did not return an ID token for this account.',
      );
    }
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    return _auth.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    await Future.wait([
      _auth.signOut(),
      _googleSignIn.signOut(),
    ]);
  }

  Future<void> deleteAccount(SharedPreferences prefs) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('No signed-in account');
    await ensureInitialized();
    // Reauthenticate the existing user; do not sign in as a different user.
    final account = await _googleSignIn.authenticate();
    final token = account.authentication.idToken;
    if (token == null) throw StateError('Missing Google authentication token');
    await runAccountDeletion(
      reauthenticate: () async {
        await user.reauthenticateWithCredential(
            GoogleAuthProvider.credential(idToken: token));
      },
      removeDeviceData: () => PushNotificationService.disable(prefs),
      deleteIdentity: user.delete,
      clearLocalData: () async {
        // Firebase deletion is authoritative; local cleanup follows only after
        // success. The UI must not report failure just because Google sign-out fails.
        for (final key in prefs
            .getKeys()
            .where((key) => key.startsWith('newsup.'))
            .toList()) {
          await prefs.remove(key);
        }
      },
    );
    try {
      await _googleSignIn.signOut();
    } catch (_) {/* Firebase account is deleted. */}
  }
}
