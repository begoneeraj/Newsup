import '../utils/genz_fallback_translator.dart';

enum GovtPromiseCategory {
  metro,
  highway,
  smartCity,
  aiMission,
  semiconductor,
  socialScheme,
  defence,
  budgetAllocation,
  electionPromise,
  other,
}

extension GovtPromiseCategoryLabel on GovtPromiseCategory {
  String get label {
    switch (this) {
      case GovtPromiseCategory.metro:
        return 'Metro';
      case GovtPromiseCategory.highway:
        return 'Highway';
      case GovtPromiseCategory.smartCity:
        return 'Smart City';
      case GovtPromiseCategory.aiMission:
        return 'AI Mission';
      case GovtPromiseCategory.semiconductor:
        return 'Semiconductor';
      case GovtPromiseCategory.socialScheme:
        return 'Social Scheme';
      case GovtPromiseCategory.defence:
        return 'Defence';
      case GovtPromiseCategory.budgetAllocation:
        return 'Budget Allocation';
      case GovtPromiseCategory.electionPromise:
        return 'Election Promise';
      case GovtPromiseCategory.other:
        return 'Other';
    }
  }
}

/// Parses the lowercase-snake-case strings written by the ingestion
/// pipeline (see src/models/schemas.py::GovtPromiseCategory).
GovtPromiseCategory govtPromiseCategoryFromJson(String value) {
  switch (value) {
    case 'metro':
      return GovtPromiseCategory.metro;
    case 'highway':
      return GovtPromiseCategory.highway;
    case 'smart_city':
      return GovtPromiseCategory.smartCity;
    case 'ai_mission':
      return GovtPromiseCategory.aiMission;
    case 'semiconductor':
      return GovtPromiseCategory.semiconductor;
    case 'social_scheme':
      return GovtPromiseCategory.socialScheme;
    case 'defence':
      return GovtPromiseCategory.defence;
    case 'budget_allocation':
      return GovtPromiseCategory.budgetAllocation;
    case 'election_promise':
      return GovtPromiseCategory.electionPromise;
    case 'other':
    default:
      return GovtPromiseCategory.other;
  }
}

enum GovtPromiseStatus { announced, started, ongoing, delayed, stalled, completed, cancelled }

extension GovtPromiseStatusLabel on GovtPromiseStatus {
  String get label {
    switch (this) {
      case GovtPromiseStatus.announced:
        return 'Announced';
      case GovtPromiseStatus.started:
        return 'Started';
      case GovtPromiseStatus.ongoing:
        return 'Ongoing';
      case GovtPromiseStatus.delayed:
        return 'Delayed';
      case GovtPromiseStatus.stalled:
        return 'Stalled';
      case GovtPromiseStatus.completed:
        return 'Completed';
      case GovtPromiseStatus.cancelled:
        return 'Cancelled';
    }
  }
}

GovtPromiseStatus govtPromiseStatusFromJson(String value) {
  switch (value) {
    case 'announced':
      return GovtPromiseStatus.announced;
    case 'started':
      return GovtPromiseStatus.started;
    case 'ongoing':
      return GovtPromiseStatus.ongoing;
    case 'delayed':
      return GovtPromiseStatus.delayed;
    case 'stalled':
      return GovtPromiseStatus.stalled;
    case 'completed':
      return GovtPromiseStatus.completed;
    case 'cancelled':
    default:
      return GovtPromiseStatus.cancelled;
  }
}

/// Orthogonal to [GovtPromiseStatus]: status tracks project lifecycle stage
/// (started/ongoing/completed...), this tracks how thoroughly that status
/// has been independently verified. A promise can be status=completed while
/// implementationQuality is still onPaperOnly if the only evidence is the
/// government's own inauguration press release — see
/// src/pipeline/promise_reverification.py::_apply_business_rules for the
/// code-level rule enforcing this (fullyImplemented requires at least one
/// independent-source evidence row, not just official self-reporting).
enum GovtPromiseImplementationQuality {
  notStarted,
  onPaperOnly,
  partiallyImplemented,
  fullyImplemented,
  poorQualityImplementation,
}

extension GovtPromiseImplementationQualityLabel on GovtPromiseImplementationQuality {
  String get label {
    switch (this) {
      case GovtPromiseImplementationQuality.notStarted:
        return 'Not Started';
      case GovtPromiseImplementationQuality.onPaperOnly:
        return 'On Paper Only';
      case GovtPromiseImplementationQuality.partiallyImplemented:
        return 'Partially Implemented';
      case GovtPromiseImplementationQuality.fullyImplemented:
        return 'Fully Implemented';
      case GovtPromiseImplementationQuality.poorQualityImplementation:
        return 'Poor Quality';
    }
  }
}

GovtPromiseImplementationQuality? govtPromiseImplementationQualityFromJson(String? value) {
  switch (value) {
    case 'not_started':
      return GovtPromiseImplementationQuality.notStarted;
    case 'on_paper_only':
      return GovtPromiseImplementationQuality.onPaperOnly;
    case 'partially_implemented':
      return GovtPromiseImplementationQuality.partiallyImplemented;
    case 'fully_implemented':
      return GovtPromiseImplementationQuality.fullyImplemented;
    case 'poor_quality_implementation':
      return GovtPromiseImplementationQuality.poorQualityImplementation;
    default:
      return null;
  }
}

enum VerificationConfidence { low, medium, high }

VerificationConfidence verificationConfidenceFromJson(String value) {
  switch (value) {
    case 'high':
      return VerificationConfidence.high;
    case 'medium':
      return VerificationConfidence.medium;
    case 'low':
    default:
      return VerificationConfidence.low;
  }
}

enum PromiseEvidenceSourceType {
  parliamentQa,
  cagReport,
  prsLegislative,
  newsArticle,
  officialPib,
  mygovSchemePage,
  manifestoPdf,
  budgetDocument,
  other,
}

extension PromiseEvidenceSourceTypeLabel on PromiseEvidenceSourceType {
  String get label {
    switch (this) {
      case PromiseEvidenceSourceType.parliamentQa:
        return 'Parliament Q&A';
      case PromiseEvidenceSourceType.cagReport:
        return 'CAG Report';
      case PromiseEvidenceSourceType.prsLegislative:
        return 'PRS Legislative';
      case PromiseEvidenceSourceType.newsArticle:
        return 'News';
      case PromiseEvidenceSourceType.officialPib:
        return 'Official (PIB)';
      case PromiseEvidenceSourceType.mygovSchemePage:
        return 'Scheme Page';
      case PromiseEvidenceSourceType.manifestoPdf:
        return 'Manifesto';
      case PromiseEvidenceSourceType.budgetDocument:
        return 'Budget Document';
      case PromiseEvidenceSourceType.other:
        return 'Other';
    }
  }

  /// Whether this source counts as independent verification rather than
  /// the government's own self-reporting — same set the backend guard uses
  /// (src/pipeline/promise_reverification.py::INDEPENDENT_SOURCE_TYPES).
  bool get isIndependent =>
      this == PromiseEvidenceSourceType.parliamentQa ||
      this == PromiseEvidenceSourceType.cagReport ||
      this == PromiseEvidenceSourceType.prsLegislative;
}

PromiseEvidenceSourceType promiseEvidenceSourceTypeFromJson(String value) {
  switch (value) {
    case 'parliament_qa':
      return PromiseEvidenceSourceType.parliamentQa;
    case 'cag_report':
      return PromiseEvidenceSourceType.cagReport;
    case 'prs_legislative':
      return PromiseEvidenceSourceType.prsLegislative;
    case 'news_article':
      return PromiseEvidenceSourceType.newsArticle;
    case 'official_pib':
      return PromiseEvidenceSourceType.officialPib;
    case 'mygov_scheme_page':
      return PromiseEvidenceSourceType.mygovSchemePage;
    case 'manifesto_pdf':
      return PromiseEvidenceSourceType.manifestoPdf;
    case 'budget_document':
      return PromiseEvidenceSourceType.budgetDocument;
    case 'other':
    default:
      return PromiseEvidenceSourceType.other;
  }
}

enum PromiseEvidenceStance { supportsDone, contradictsDone, neutralUpdate }

PromiseEvidenceStance promiseEvidenceStanceFromJson(String value) {
  switch (value) {
    case 'supports_done':
      return PromiseEvidenceStance.supportsDone;
    case 'contradicts_done':
      return PromiseEvidenceStance.contradictsDone;
    case 'neutral_update':
    default:
      return PromiseEvidenceStance.neutralUpdate;
  }
}

class PromiseEvidence {
  final String id;
  final String promiseId;
  final PromiseEvidenceSourceType sourceType;
  final String sourceUrl;
  final PromiseEvidenceStance stance;
  final String excerptSummary;
  final DateTime observedAt;

  const PromiseEvidence({
    required this.id,
    required this.promiseId,
    required this.sourceType,
    required this.sourceUrl,
    required this.stance,
    required this.excerptSummary,
    required this.observedAt,
  });

  factory PromiseEvidence.fromJson(Map<String, dynamic> json) {
    return PromiseEvidence(
      id: json['id'] as String,
      promiseId: json['promise_id'] as String,
      sourceType: promiseEvidenceSourceTypeFromJson(json['source_type'] as String),
      sourceUrl: json['source_url'] as String? ?? '',
      stance: promiseEvidenceStanceFromJson(json['stance'] as String),
      excerptSummary: json['excerpt_summary'] as String,
      observedAt: DateTime.parse(json['observed_at'] as String),
    );
  }
}

class GovtPromise {
  final String id;
  final String projectName;
  final String projectSlug;
  final GovtPromiseCategory category;
  final String announcingBody;
  final String stateOrNational;
  final String? state;
  final String? party;
  final int? electionYear;
  final GovtPromiseStatus currentStatus;
  final double? budgetAllocatedCrore;
  final double? budgetSpentCrore;
  final bool brokenPromiseFlag;
  final String? brokenPromiseDetail;
  final String? beneficiaries;
  final String headlinePlain;
  final String aiSummary;

  /// Optional shorter, punchier rephrase of [aiSummary] for GenZ voice.
  /// Falls back to a word-substitution translation when null.
  final String? genzSummary;

  final List<String> keyFacts;
  final String? nextMilestone;
  final List<String> verificationSources;
  final GovtPromiseImplementationQuality? implementationQuality;
  final VerificationConfidence verificationConfidence;
  final String? officialClaim;
  final String? groundReality;
  final DateTime? lastVerifiedAt;
  final DateTime lastUpdated;

  const GovtPromise({
    required this.id,
    required this.projectName,
    required this.projectSlug,
    required this.category,
    required this.announcingBody,
    required this.stateOrNational,
    this.state,
    this.party,
    this.electionYear,
    required this.currentStatus,
    this.budgetAllocatedCrore,
    this.budgetSpentCrore,
    this.brokenPromiseFlag = false,
    this.brokenPromiseDetail,
    this.beneficiaries,
    required this.headlinePlain,
    required this.aiSummary,
    this.genzSummary,
    this.keyFacts = const [],
    this.nextMilestone,
    this.verificationSources = const [],
    this.implementationQuality,
    this.verificationConfidence = VerificationConfidence.low,
    this.officialClaim,
    this.groundReality,
    this.lastVerifiedAt,
    required this.lastUpdated,
  });

  String displaySummary(bool genzVoice) =>
      genzVoice ? (genzSummary ?? genzFallbackTranslate(aiSummary)) : aiSummary;

  factory GovtPromise.fromJson(Map<String, dynamic> json) {
    return GovtPromise(
      id: json['id'] as String,
      projectName: json['project_name'] as String,
      projectSlug: json['project_slug'] as String,
      category: govtPromiseCategoryFromJson(json['category'] as String),
      announcingBody: json['announcing_body'] as String,
      stateOrNational: json['state_or_national'] as String,
      state: json['state'] as String?,
      party: json['party'] as String?,
      electionYear: json['election_year'] as int?,
      currentStatus: govtPromiseStatusFromJson(json['current_status'] as String),
      budgetAllocatedCrore: (json['budget_allocated_crore'] as num?)?.toDouble(),
      budgetSpentCrore: (json['budget_spent_crore'] as num?)?.toDouble(),
      brokenPromiseFlag: json['broken_promise_flag'] as bool? ?? false,
      brokenPromiseDetail: json['broken_promise_detail'] as String?,
      beneficiaries: json['beneficiaries'] as String?,
      headlinePlain: json['headline_plain'] as String,
      aiSummary: json['ai_summary'] as String,
      genzSummary: json['genz_summary'] as String?,
      keyFacts: (json['key_facts'] as List<dynamic>? ?? []).map((e) => e as String).toList(),
      nextMilestone: json['next_milestone'] as String?,
      verificationSources:
          (json['verification_sources'] as List<dynamic>? ?? []).map((e) => e as String).toList(),
      implementationQuality:
          govtPromiseImplementationQualityFromJson(json['implementation_quality'] as String?),
      verificationConfidence:
          verificationConfidenceFromJson(json['verification_confidence'] as String? ?? 'low'),
      officialClaim: json['official_claim'] as String?,
      groundReality: json['ground_reality'] as String?,
      lastVerifiedAt: json['last_verified_at'] == null
          ? null
          : DateTime.parse(json['last_verified_at'] as String),
      lastUpdated: DateTime.parse(json['last_updated'] as String),
    );
  }
}
