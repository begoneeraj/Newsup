import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../release_config.dart';
import '../theme/theme_providers.dart';

class ConsentScreen extends ConsumerStatefulWidget {
  const ConsentScreen({super.key});
  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  bool _adult = false;
  bool _agreed = false;
  bool _saving = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Before you continue')),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          Text('Welcome to TruthLens India',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 20),
          const Text(
              'This service is for adults aged 18 and over. It covers news that may include violence, conflict and other sensitive topics.'),
          const SizedBox(height: 16),
          const Text(
              'When you sign in, Google provides your name, email, profile picture and account ID to Firebase for authentication. '
              'Bookmarks and reading progress stay on this device. Content services and fonts receive technical connection data. '
              'Notifications are optional and off until you choose to enable them. There are no ads or analytics SDKs configured.'),
          const SizedBox(height: 16),
          const Text(
              'AI-assisted summaries, verdicts and confidence scores can be inaccurate. Check the linked original sources.'),
          TextButton(
              onPressed: () => context.push('/legal'),
              child:
                  const Text('Read privacy policy, terms & publisher details')),
          CheckboxListTile(
              value: _adult,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _adult = value ?? false),
              title: const Text('I am 18 years old or older'),
              controlAffinity: ListTileControlAffinity.leading),
          CheckboxListTile(
              value: _agreed,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _agreed = value ?? false),
              title: const Text(
                  'I agree to the terms and acknowledge the privacy notice'),
              controlAffinity: ListTileControlAffinity.leading),
          FilledButton(
              onPressed: !_adult || !_agreed || _saving
                  ? null
                  : () async {
                      setState(() => _saving = true);
                      final prefs = ref.read(sharedPreferencesProvider);
                      final saved = await prefs.setString(
                          ReleaseConfig.consentKey,
                          ReleaseConfig.policyVersion);
                      if (!context.mounted) return;
                      if (saved) {
                        context.go('/');
                      } else {
                        setState(() => _saving = false);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text(
                                'Could not save your choice. Please try again.')));
                      }
                    },
              child: Text(_saving ? 'Saving…' : 'Continue')),
          const SizedBox(height: 12),
          const Text(
              'If you are under 18 or do not agree, please close the app. You can delete your account from the account controls.'),
        ]),
      );
}
