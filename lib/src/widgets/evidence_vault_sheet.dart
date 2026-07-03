import 'package:flutter/material.dart';

import '../models/crisis_report.dart';

class EvidenceVaultSheet extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF242426),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Row(
                  children: [
                    const Icon(Icons.folder_outlined, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Evidence Vault',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: evidenceItems.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = evidenceItems[index];
                    return ListTile(
                      leading: Icon(_iconFor(item.type)),
                      title: Text(item.title),
                      subtitle: Text(
                        item.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.open_in_new, size: 16),
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
