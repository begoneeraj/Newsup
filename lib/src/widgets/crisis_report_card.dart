import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/crisis_report.dart';
import '../theme/app_colors.dart';

class CrisisReportCard extends StatelessWidget {
  const CrisisReportCard({super.key, required this.report, required this.onTap});

  final CrisisReport report;
  final VoidCallback onTap;

  static const String _officialEmail = 'minister.edu@gov.in';

  Color get _statusColor {
    switch (report.status) {
      case CrisisStatus.unresolved:
        return AppColors.falseRed;
      case CrisisStatus.partiallyResolved:
        return AppColors.misleadingAmber;
      case CrisisStatus.resolved:
        return AppColors.verifiedGreen;
    }
  }

  Future<void> _demandAccountability(BuildContext context) async {
    final subject = 'Accountability Demand: ${report.title}';
    final body =
        'To the concerned authority,\n\n'
        'This matter — "${report.title}" — has remained '
        '${report.status.label.toLowerCase()} for ${report.daysSinceEvent} days, '
        'with only ${report.remedialActionsCount} remedial action(s) taken and '
        '${report.rtiFilingsAnswered} of ${report.rtiFilingsTotal} RTI filings answered.\n\n'
        'We demand a transparent, public update on the status of this matter.\n\n'
        '— Sent via NewsUp';

    final uri = Uri(
      scheme: 'mailto',
      path: _officialEmail,
      queryParameters: {'subject': subject, 'body': body},
    );

    final launched = await launchUrl(uri);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open an email app.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _statusColor),
                    ),
                    child: Text(
                      report.status.label.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${report.daysSinceEvent} days',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white70,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                report.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.gavel_outlined, size: 14, color: Colors.white38),
                  const SizedBox(width: 4),
                  Text(
                    '${report.remedialActionsCount} remedial actions',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white54,
                        ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.description_outlined, size: 14, color: Colors.white38),
                  const SizedBox(width: 4),
                  Text(
                    'RTI ${report.rtiFilingsAnswered}/${report.rtiFilingsTotal}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white54,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _demandAccountability(context),
                  icon: const Icon(Icons.mail_outline, size: 16),
                  label: const Text('Demand Accountability'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
