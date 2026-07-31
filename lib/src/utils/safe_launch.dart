import 'package:url_launcher/url_launcher.dart';

import '../security_config.dart';

/// `true` only for `https://` URLs. Fact-check/source/promise links come
/// from Supabase-hosted content rather than a fixed allowlist, so every
/// outbound link must be checked at launch time — a plain `http://` link
/// (or any other scheme) is never opened.
bool isSecureUrl(String url) => Uri.tryParse(url)?.scheme == 'https';

/// Launches [url] only if [isSecureUrl]; otherwise no-ops and returns
/// `false`. Use this instead of calling `launchUrl` directly anywhere a
/// URL comes from app content rather than a hardcoded literal.
Future<bool> launchSecureUrl(String url, {LaunchMode mode = LaunchMode.platformDefault}) {
  if (!isSecureUrl(url)) {
    secureLog('Blocked launch of non-HTTPS URL: $url');
    return Future.value(false);
  }
  return launchUrl(Uri.parse(url), mode: mode);
}
