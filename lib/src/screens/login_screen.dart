import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/auth_service.dart';
import '../theme/app_theme_data.dart';
import '../theme/theme_providers.dart';
import '../widgets/google_logo.dart';

/// Sole entry point into the app — every screen behind it is gated on a
/// signed-in Firebase user (see appRouterProvider's redirect), and Google is
/// the only identity provider, so there's nothing here but the one button.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  bool _signingIn = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    final curved = CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic);
    _fade = curved;
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(curved);
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _signingIn = true;
      _error = null;
    });
    try {
      await AuthService.instance.signInWithGoogle();
      // On success authStateProvider emits the new user and the router's
      // redirect takes it from here — nothing to navigate to manually.
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        setState(() => _error = null);
      } else {
        setState(() => _error = 'Google sign-in failed. Please try again.');
      }
    } on FirebaseAuthException catch (_) {
      setState(() => _error = 'Could not sign you in. Please try again.');
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(appThemeDataProvider);

    return Scaffold(
      backgroundColor: theme.bg,
      body: Stack(
        children: [
          Positioned.fill(child: _BackgroundGlow(theme: theme)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: FadeTransition(
                opacity: _fade,
                child: SlideTransition(
                  position: _slide,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _BrandMark(theme: theme),
                      const SizedBox(height: 32),
                      Text(
                        'TruthLens India',
                        textAlign: TextAlign.center,
                        style: theme.displayFont(fontSize: 26, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Sign in with Google to unlock fact checks, crisis\n'
                        'tracking, and bookmarks that follow you everywhere.',
                        textAlign: TextAlign.center,
                        style: theme
                            .bodyFont(fontSize: 14, color: theme.textMuted, fontWeight: FontWeight.w500)
                            .copyWith(height: 1.5),
                      ),
                      const SizedBox(height: 32),
                      _FeatureRow(theme: theme),
                      const SizedBox(height: 36),
                      _GoogleSignInButton(
                        loading: _signingIn,
                        onPressed: _signIn,
                        theme: theme,
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        child: _error == null
                            ? const SizedBox(width: double.infinity)
                            : Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: _ErrorBanner(message: _error!, theme: theme),
                              ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'One tap, no passwords to remember — your account stays\nyours, always.',
                        textAlign: TextAlign.center,
                        style: theme.bodyFont(fontSize: 12, color: theme.textDisabled, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Soft radial accent glow anchored behind the brand mark — the same "one
/// warm light source" trick used behind the bottom nav's active-tab dot,
/// scaled up to fill the top of the screen instead of a single pixel.
class _BackgroundGlow extends StatelessWidget {
  const _BackgroundGlow({required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.7),
      child: Container(
        width: 340,
        height: 340,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              theme.accent.withValues(alpha: theme.brightness == Brightness.dark ? 0.22 : 0.14),
              theme.accent.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [theme.accent.withValues(alpha: 0.22), theme.accent.withValues(alpha: 0.08)],
        ),
        border: Border.all(color: theme.accent.withValues(alpha: 0.25), width: 1.5),
      ),
      child: Icon(Icons.verified_user_rounded, size: 42, color: theme.accent),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.theme});

  final AppThemeData theme;

  static const _features = [
    (Icons.fact_check_outlined, 'Verified'),
    (Icons.bolt_outlined, 'Real-time'),
    (Icons.lock_outline_rounded, 'Private'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final (icon, label) in _features)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.surfaceVariant,
                  border: Border.all(color: theme.border),
                ),
                child: Icon(icon, size: 18, color: theme.textMuted),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: theme.bodyFont(fontSize: 11, color: theme.textMuted, fontWeight: FontWeight.w600),
              ),
            ],
          ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.theme});

  final String message;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: theme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.bodyFont(fontSize: 13, color: theme.error, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({
    required this.loading,
    required this.onPressed,
    required this.theme,
  });

  final bool loading;
  final VoidCallback onPressed;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 6,
        shadowColor: theme.accent.withValues(alpha: 0.25),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: loading ? null : onPressed,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFDADCE0)),
            ),
            alignment: Alignment.center,
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GoogleLogo(size: 20),
                      SizedBox(width: 12),
                      Text(
                        'Continue with Google',
                        style: _buttonTextStyle,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Google's own branding guidelines call for a neutral dark-grey label
/// regardless of app theme, since the button itself is always white — using
/// [AppThemeData.bodyFont] here would put a themed color on a fixed-white
/// surface and break contrast in dark mode.
const _buttonTextStyle = TextStyle(
  fontSize: 15,
  fontWeight: FontWeight.w600,
  color: Color(0xFF3C4043),
);
