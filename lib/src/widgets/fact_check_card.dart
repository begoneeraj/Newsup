import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/fact_check.dart';
import '../theme/theme_providers.dart';
import 'status_stamp.dart';

class FactCheckCard extends ConsumerWidget {
  const FactCheckCard({super.key, required this.factCheck, required this.onTap});

  final FactCheck factCheck;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);
    final genz = theme.isGenz;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusStamp(status: factCheck.status),
              const SizedBox(height: 12),
              Text(
                factCheck.displayClaim(genz),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.displayFont(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                factCheck.origin,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.bodyFont(fontSize: 12, color: theme.textMuted),
              ),
              const SizedBox(height: 12),
              Divider(height: 1, color: theme.border),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.people_outline, size: 14, color: theme.textMuted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${factCheck.independentConfirmations} confirmations'
                      '${factCheck.officialConfirmation ? ' · official' : ''}',
                      overflow: TextOverflow.ellipsis,
                      style: theme.bodyFont(fontSize: 12, color: theme.textMuted),
                    ),
                  ),
                  Text(
                    '${factCheck.evidenceConfidence}%',
                    style: theme.monoFont(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.accent,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
