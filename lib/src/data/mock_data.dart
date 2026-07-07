import '../models/crisis_report.dart';
import '../models/fact_check.dart';
import '../theme/app_colors.dart';

/// Static, manually curated mock data. No backend calls — wired through
/// Riverpod providers in `providers/`.
class MockData {
  MockData._();

  static final List<FactCheck> factChecks = [
    FactCheck(
      id: 'fc-001',
      claimText:
          'Viral message claims a new government scheme deposits ₹15,000 '
          'directly into every citizen\'s bank account this month.',
      origin: 'WhatsApp forward, widely shared July 2026',
      status: FactCheckStatus.falseClaim,
      genzSummary: 'That "₹15,000 to everyone" WhatsApp msg? Fake.',
      evidenceConfidence: 92,
      sourceReliability: SourceReliability.high,
      independentConfirmations: 4,
      officialConfirmation: true,
      sources: [
        SourceRef(
          title: 'PIB Fact Check clarification',
          url: 'https://pib.gov.in/factcheck/example-1',
          publishedAt: DateTime(2026, 6, 28),
        ),
        SourceRef(
          title: 'Ministry of Finance press release',
          url: 'https://finmin.nic.in/press/example-1',
          publishedAt: DateTime(2026, 6, 29),
        ),
      ],
      expertAnalysis:
          'No such scheme exists in the current budget cycle. The claim '
          'reuses a template seen in similar hoaxes since 2021.',
      createdAt: DateTime(2026, 6, 30),
    ),
    FactCheck(
      id: 'fc-002',
      claimText:
          'A regional news channel reported that a major dam experienced '
          'a structural crack and is at risk of failure.',
      origin: 'Regional TV broadcast, clipped and shared on social media',
      status: FactCheckStatus.misleading,
      genzSummary: 'Dam did NOT crack — a seepage check got clickbaited.',
      evidenceConfidence: 61,
      sourceReliability: SourceReliability.med,
      independentConfirmations: 2,
      officialConfirmation: false,
      sources: [
        SourceRef(
          title: 'State irrigation department statement',
          url: 'https://example-state.gov.in/irrigation/statement',
          publishedAt: DateTime(2026, 6, 20),
        ),
      ],
      expertAnalysis:
          'A minor seepage inspection was misreported as a structural '
          'failure. Engineers confirm the dam is within safety tolerances, '
          'but routine monitoring has been increased.',
      createdAt: DateTime(2026, 6, 21),
    ),
    FactCheck(
      id: 'fc-003',
      claimText: 'Official data shows unemployment in the informal sector fell '
          'below 4% last quarter.',
      origin: 'Government press briefing, quoted out of context online',
      status: FactCheckStatus.partlyTrue,
      evidenceConfidence: 74,
      sourceReliability: SourceReliability.high,
      independentConfirmations: 3,
      officialConfirmation: true,
      sources: [
        SourceRef(
          title: 'Periodic Labour Force Survey release',
          url: 'https://mospi.gov.in/plfs/example',
          publishedAt: DateTime(2026, 5, 15),
        ),
      ],
      expertAnalysis:
          'The 4% figure applies to a narrow urban sub-segment, not the '
          'informal sector nationally, which remains considerably higher.',
      createdAt: DateTime(2026, 5, 16),
    ),
    FactCheck(
      id: 'fc-004',
      claimText: 'A satirical article claiming a state assembly passed a law '
          'requiring citizens to greet each other in Sanskrit is being '
          'shared as real news.',
      origin: 'Satire website, screenshot stripped of context',
      status: FactCheckStatus.satire,
      evidenceConfidence: 88,
      sourceReliability: SourceReliability.high,
      independentConfirmations: 1,
      officialConfirmation: false,
      sources: [
        SourceRef(
          title: 'Original satire publication masthead',
          url: 'https://example-satire.in/sanskrit-greeting-law',
          publishedAt: DateTime(2026, 6, 10),
        ),
      ],
      expertAnalysis:
          'The originating site is a declared satire outlet; no such bill '
          'exists in any state legislative record.',
      createdAt: DateTime(2026, 6, 11),
    ),
    FactCheck(
      id: 'fc-005',
      claimText:
          'Reports circulating that a metro rail extension has been fully '
          'cancelled due to funding withdrawal.',
      origin: 'Local news aggregator, single unnamed source',
      status: FactCheckStatus.unverified,
      evidenceConfidence: 35,
      sourceReliability: SourceReliability.low,
      independentConfirmations: 0,
      officialConfirmation: false,
      sources: [
        SourceRef(
          title: 'Aggregator report (unverified)',
          url: 'https://example-aggregator.in/metro-cancel',
          publishedAt: DateTime(2026, 7, 1),
        ),
      ],
      expertAnalysis: null,
      createdAt: DateTime(2026, 7, 2),
    ),
  ];

  static final List<CrisisReport> crisisReports = [
    CrisisReport(
      id: 'cr-001',
      title: 'National entrance exam (NEET) leaks',
      status: CrisisStatus.unresolved,
      eventStartDate: DateTime.now().subtract(const Duration(days: 712)),
      remedialActionsCount: 2,
      rtiFilingsTotal: 14,
      rtiFilingsAnswered: 1,
      timelineEvents: [
        TimelineEvent(
          date: DateTime.now().subtract(const Duration(days: 712)),
          title: 'Paper leak reported',
          description:
              'Multiple exam centers flagged for irregularities; leaked '
              'question papers surface on messaging platforms hours before '
              'the exam.',
          statusColor: AppColors.falseRed,
        ),
        TimelineEvent(
          date: DateTime.now().subtract(const Duration(days: 690)),
          title: 'Investigation ordered',
          description:
              'A central investigating agency is assigned to probe the '
              'leak across implicated states.',
          statusColor: AppColors.misleadingAmber,
        ),
        TimelineEvent(
          date: DateTime.now().subtract(const Duration(days: 520)),
          title: 'Partial arrests made',
          description:
              'A handful of intermediaries are arrested; the source of the '
              'leaked paper remains unconfirmed.',
          statusColor: AppColors.misleadingAmber,
        ),
        TimelineEvent(
          date: DateTime.now().subtract(const Duration(days: 120)),
          title: 'RTI responses stall',
          description: 'Most Right to Information filings on the investigation '
              'status remain unanswered past the statutory deadline.',
          statusColor: AppColors.falseRed,
        ),
      ],
      evidenceItems: [
        const EvidenceItem(
          title: 'Original FIR copy',
          url: 'https://example.gov.in/evidence/neet-fir.pdf',
          type: EvidenceType.pdf,
        ),
        const EvidenceItem(
          title: 'Parliamentary committee hearing (live archive)',
          url: 'https://sansad.in/example/neet-hearing',
          type: EvidenceType.live,
        ),
        const EvidenceItem(
          title: 'RTI response tracker document',
          url: 'https://example.gov.in/evidence/neet-rti-tracker',
          type: EvidenceType.document,
        ),
      ],
    ),
    CrisisReport(
      id: 'cr-002',
      title: 'Industrial gas leak, riverside township',
      status: CrisisStatus.partiallyResolved,
      eventStartDate: DateTime.now().subtract(const Duration(days: 260)),
      remedialActionsCount: 6,
      rtiFilingsTotal: 8,
      rtiFilingsAnswered: 5,
      timelineEvents: [
        TimelineEvent(
          date: DateTime.now().subtract(const Duration(days: 260)),
          title: 'Leak detected',
          description: 'A chemical storage failure releases toxic gas near a '
              'residential township; emergency evacuation ordered.',
          statusColor: AppColors.falseRed,
        ),
        TimelineEvent(
          date: DateTime.now().subtract(const Duration(days: 255)),
          title: 'Medical camps established',
          description:
              'State health department sets up triage camps for affected '
              'residents.',
          statusColor: AppColors.misleadingAmber,
        ),
        TimelineEvent(
          date: DateTime.now().subtract(const Duration(days: 90)),
          title: 'Compensation disbursed (partial)',
          description:
              'Interim compensation released to roughly 60% of registered '
              'claimants.',
          statusColor: AppColors.misleadingAmber,
        ),
        TimelineEvent(
          date: DateTime.now().subtract(const Duration(days: 30)),
          title: 'Plant safety audit completed',
          description:
              'Independent auditors submit findings; full public release '
              'still pending.',
          statusColor: AppColors.verifiedGreen,
        ),
      ],
      evidenceItems: [
        const EvidenceItem(
          title: 'Pollution control board inspection report',
          url: 'https://example.gov.in/evidence/gasleak-inspection.pdf',
          type: EvidenceType.pdf,
        ),
        const EvidenceItem(
          title: 'Compensation disbursement ledger',
          url: 'https://example.gov.in/evidence/gasleak-ledger',
          type: EvidenceType.document,
        ),
      ],
    ),
    CrisisReport(
      id: 'cr-003',
      title: 'Urban flood drainage failure inquiry',
      status: CrisisStatus.resolved,
      eventStartDate: DateTime.now().subtract(const Duration(days: 430)),
      remedialActionsCount: 9,
      rtiFilingsTotal: 5,
      rtiFilingsAnswered: 5,
      timelineEvents: [
        TimelineEvent(
          date: DateTime.now().subtract(const Duration(days: 430)),
          title: 'Flash flooding overwhelms drains',
          description:
              'Heavy monsoon rainfall exposes years of deferred drainage '
              'maintenance, flooding low-lying wards.',
          statusColor: AppColors.falseRed,
        ),
        TimelineEvent(
          date: DateTime.now().subtract(const Duration(days: 400)),
          title: 'Municipal audit ordered',
          description:
              'City council commissions an independent audit of drainage '
              'contracts over the past decade.',
          statusColor: AppColors.misleadingAmber,
        ),
        TimelineEvent(
          date: DateTime.now().subtract(const Duration(days: 200)),
          title: 'Contractor penalties issued',
          description:
              'Two contracting firms fined for substandard work; funds '
              'redirected to emergency desilting.',
          statusColor: AppColors.misleadingAmber,
        ),
        TimelineEvent(
          date: DateTime.now().subtract(const Duration(days: 45)),
          title: 'Remediation certified complete',
          description:
              'Independent engineers certify drainage capacity restored '
              'to design specification across all affected wards.',
          statusColor: AppColors.verifiedGreen,
        ),
      ],
      evidenceItems: [
        const EvidenceItem(
          title: 'Municipal audit final report',
          url: 'https://example.gov.in/evidence/flood-audit.pdf',
          type: EvidenceType.pdf,
        ),
        const EvidenceItem(
          title: 'Engineering certification document',
          url: 'https://example.gov.in/evidence/flood-certification',
          type: EvidenceType.document,
        ),
      ],
    ),
  ];
}
