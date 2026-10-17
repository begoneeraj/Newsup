import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../release_config.dart';
import '../utils/safe_launch.dart';

/// Available before sign-in as well as from the account menu.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  static Future<void> contact(BuildContext context, {String? itemId}) async {
    if (ReleaseConfig.supportEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Support details must be configured before public release.'),
      ));
      return;
    }
    final uri = Uri(
      scheme: 'mailto',
      path: ReleaseConfig.supportEmail,
      query:
          'subject=${Uri.encodeComponent(itemId == null ? 'TruthLens India support' : 'TruthLens India correction: $itemId')}',
    );
    var opened = false;
    try {
      opened = await launchUrl(uri);
    } catch (_) {/* Show fallback below. */}
    if (!opened && context.mounted) {
      await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('Contact support'),
                content: SelectableText('Email ${ReleaseConfig.supportEmail}'
                    '${itemId == null ? '' : '\nInclude article ID: $itemId'}'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'))
                ],
              ));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Privacy, terms & publisher')),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          Text('TruthLens India',
              style: Theme.of(context).textTheme.headlineSmall),
          const Text('Policy version: ${ReleaseConfig.policyVersion}'),
          const SizedBox(height: 16),
          Text(ReleaseConfig.publisher.isEmpty
              ? 'Preview build: publisher details are awaiting confirmation.'
              : 'Published by ${ReleaseConfig.publisher}'),
          if (ReleaseConfig.supportEmail.isNotEmpty)
            const SelectableText(ReleaseConfig.supportEmail),
          TextButton(
              onPressed: () => contact(context),
              child: const Text('Support, corrections & privacy requests')),
          if (ReleaseConfig.policyBaseUrl.isNotEmpty)
            TextButton(
                onPressed: () async {
                  final opened =
                      await launchSecureUrl(ReleaseConfig.policyBaseUrl);
                  if (!opened && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Could not open the policy website.')));
                  }
                },
                child: const Text('Public policy and contact website')),
          const _Section(
              'Privacy notice',
              'Google sign-in provides your name, email address, profile picture and account identifier to Firebase Authentication. '
                  'We use these to authenticate you and display your profile. Your Google password is not provided to this app. '
                  'Firebase and Google process authentication and technical connection data; Supabase serves news content. '
                  'Requests to these services, Google Fonts, profile-image hosts and linked publishers expose connection information such as your IP address. '
                  'Bookmarks, reading-game progress, appearance preferences and the policy acknowledgement are stored on this device. '
                  'This app has no advertising or analytics SDK configured and does not request contacts, location, microphone or camera access. '
                  'Public news is processed by our backend using AI; your sign-in profile is not sent to the news-analysis model.'),
          const _Section(
              'Notifications and device data',
              'Push notifications are optional. A separate choice is required before permission is requested and a device token is registered. '
                  'If enabled, Firebase Cloud Messaging and Supabase process the token to deliver updates. '
                  'You can withdraw this choice from Account → Privacy & account controls. '
                  'Disabling notifications removes this device’s server registration and invalidates delivery. '
                  'If the request fails, retry or contact support about legacy records or inaccessible devices.'),
          const _Section(
              'Retention and deletion',
              'Your Firebase account profile is retained until you delete your app account. '
                  'Account → Privacy & account controls → Delete account removes the Firebase account and local preferences, bookmarks and progress. '
                  'It does not delete your Google account. Reauthentication may be required. '
                  'You can also request deletion, access or correction through the public support contact, including without reinstalling the app. '
                  'We may verify ownership before processing a request. Provider backups and security logs follow their configured retention and may not be erased immediately. '
                  'Content you share to other apps is controlled by those recipients.'),
          const _Section(
              'Terms of use',
              'Use TruthLens India lawfully. Do not abuse the service, interfere with its security, impersonate others or infringe intellectual-property rights. '
                  'Original reporting belongs to its respective publishers; links do not imply endorsement or a licence to republish. '
                  'The app offers automated information and analysis, not professional legal, medical or financial advice. '
                  'There are no in-app purchases or subscriptions in this release. '
                  'We may correct or remove content and restrict abusive access. Nothing in these terms excludes rights that cannot lawfully be excluded. '
                  'This release is for adults aged 18 and over. Applicable Indian law governs these terms, subject to mandatory rights and competent courts. '
                  'Material policy changes will require a new acknowledgement.'),
          const _Section(
              'Editorial standards and ownership',
              'TruthLens India is an independent news aggregation and AI-assisted analysis app, not a government service. '
                  'Automated verdicts and confidence scores can be wrong; they are not guarantees or proof of human expert review. '
                  'Read the original linked sources and dates before relying on a claim. A claim labelled unverified is not established as fact. '
                  'Source attribution must identify the original publisher or author. '
                  'Report missing sources, inaccurate claims, copyright concerns or harmful content using the correction contact. '
                  'Include the article ID, the concern and supporting evidence. The publisher is Pushpraj singh prashant. '
                  'Contact begoneraj@gmail.com for support, privacy or grievances. We aim to acknowledge complaints within 24 hours and resolve them within 15 days, '
                  'or explain a delay; applicable statutory deadlines take precedence.'),
        ]),
      );
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.body);
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(body),
        ]),
      );
}
