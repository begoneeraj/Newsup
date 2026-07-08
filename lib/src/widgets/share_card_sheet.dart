import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../models/fact_check.dart';
import '../theme/app_theme_data.dart';
import '../theme/theme_providers.dart';
import 'confidence_meter.dart';

/// Shows a bottom sheet preview of a shareable verdict card for [factCheck],
/// with a button that renders it to a PNG (via [RepaintBoundary]) and opens
/// the OS share sheet. This is the app's main organic-distribution surface —
/// a verdict screenshot reaching a WhatsApp group is worth more than any
/// in-app feature.
Future<void> showShareCardSheet(BuildContext context, WidgetRef ref, FactCheck factCheck) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _ShareCardSheet(factCheck: factCheck),
  );
}

class _ShareCardSheet extends ConsumerStatefulWidget {
  const _ShareCardSheet({required this.factCheck});

  final FactCheck factCheck;

  @override
  ConsumerState<_ShareCardSheet> createState() => _ShareCardSheetState();
}

class _ShareCardSheetState extends ConsumerState<_ShareCardSheet> {
  final _boundaryKey = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final boundary = _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      if (!mounted) return;
      await Share.shareXFiles(
        [XFile.fromData(bytes, mimeType: 'image/png', name: 'truthlens_india_verdict.png')],
        text: 'Fact-checked by TruthLens India',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not create the share image.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(appThemeDataProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: theme.border, borderRadius: BorderRadius.circular(2)),
            ),
            RepaintBoundary(
              key: _boundaryKey,
              child: _ShareableFactCheckCard(factCheck: widget.factCheck, theme: theme),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _sharing ? null : _share,
                icon: _sharing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.share_outlined),
                label: Text(_sharing ? 'Preparing…' : 'Share'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareableFactCheckCard extends StatelessWidget {
  const _ShareableFactCheckCard({required this.factCheck, required this.theme});

  final FactCheck factCheck;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    final color = theme.statusColor(factCheck.status);

    return Container(
      width: 320,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color),
            ),
            child: Text(
              factCheck.status.label.toUpperCase(),
              style: theme.bodyFont(fontSize: 12, fontWeight: FontWeight.w800, color: color),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            factCheck.claimText,
            style: theme.displayFont(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            factCheck.origin,
            style: theme.bodyFont(fontSize: 12, color: theme.textMuted),
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: theme.border),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                'Evidence confidence',
                style: theme.bodyFont(fontSize: 12, color: theme.textMuted),
              ),
              const Spacer(),
              ConfidenceMeter(confidence: factCheck.evidenceConfidence, color: color),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(Icons.verified_outlined, size: 14, color: theme.accent),
              const SizedBox(width: 4),
              Text(
                'Verified by TruthLens India',
                style: theme.bodyFont(fontSize: 12, fontWeight: FontWeight.w700, color: theme.accent),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
