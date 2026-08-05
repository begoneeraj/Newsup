import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

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
}
