import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/crisis_report.dart';
import '../theme/theme_providers.dart';

class EvidenceVaultSheet extends ConsumerWidget {
  const EvidenceVaultSheet({super.key, required this.evidenceItems});

  final List<EvidenceItem> evidenceItems;

  static Future<void> show(BuildContext context, List<EvidenceItem> items) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EvidenceVaultSheet(evidenceItems: items),
    );
  }

  IconData _iconFor(EvidenceType type) {
    switch (type) {
      case EvidenceType.pdf:
        return Icons.picture_as_pdf_outlined;
      case EvidenceType.live:
        return Icons.sensors;
      case EvidenceType.document:
        return Icons.description_outlined;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeDataProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Row(
                  children: [
                    Icon(Icons.folder_outlined, size: 20, color: theme.textMuted),
                    const SizedBox(width: 8),
                    Text(
                      'Evidence Vault',
                      style: theme.displayFont(fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: theme.border),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  itemCount: evidenceItems.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: theme.border),
                  itemBuilder: (context, index) {
                    final item = evidenceItems[index];
                    return ListTile(
                      leading: Icon(_iconFor(item.type), color: theme.textMuted),
                      title: Text(item.title, style: theme.bodyFont(fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        item.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodyFont(fontSize: 12, color: theme.textMuted),
                      ),
                      trailing: Icon(Icons.open_in_new, size: 16, color: theme.textMuted),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
