/// Public publisher information supplied by the release build. Never put
/// credentials in these values. Missing details block store submission.
class ReleaseConfig {
  static const publisher = String.fromEnvironment('PUBLISHER_NAME',
      defaultValue: 'Pushpraj singh prashant');
  static const supportEmail = String.fromEnvironment('SUPPORT_EMAIL',
      defaultValue: 'begoneraj@gmail.com');
  static const policyBaseUrl = String.fromEnvironment('POLICY_BASE_URL');
  static const playStore =
      bool.fromEnvironment('PLAY_STORE', defaultValue: false);
  static const policyVersion = '2026-10-17';
  static const consentKey = 'newsup.policyAcknowledgement';
  static const storeUrl =
      'https://play.google.com/store/apps/details?id=com.begoneeraj.newsup';

  static bool get publisherConfigured =>
      publisher.trim().isNotEmpty &&
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(supportEmail) &&
      Uri.tryParse(policyBaseUrl)?.scheme == 'https' &&
      (Uri.tryParse(policyBaseUrl)?.host.isNotEmpty ?? false);
}
