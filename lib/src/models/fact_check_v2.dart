/// Claim-level, legally-safe fact-check layer (see
/// supabase/migrations/0006_source_tracking_and_fact_checks_v2.sql and
/// src/ai_processor/groq_processor.py::_FACT_CHECK_V2_SYSTEM_PROMPT). Never
/// accuses an outlet — only cites official sources as evidence. Deliberately
/// a distinct vocabulary from FactCheckStatus (VERIFIED/FALSE/MISLEADING/...).
enum FactCheckV2Status { verified, disputed, needsMoreInfo }

extension FactCheckV2StatusLabel on FactCheckV2Status {
  String get label {
    switch (this) {
      case FactCheckV2Status.verified:
        return 'Verified';
      case FactCheckV2Status.disputed:
        return 'Disputed';
      case FactCheckV2Status.needsMoreInfo:
        return 'Needs More Info';
    }
  }

  String get emoji {
    switch (this) {
      case FactCheckV2Status.verified:
        return '✅';
      case FactCheckV2Status.disputed:
        return '⚠️';
      case FactCheckV2Status.needsMoreInfo:
        return '🔍';
    }
  }
}

FactCheckV2Status factCheckV2StatusFromJson(String value) {
  switch (value) {
    case 'VERIFIED':
      return FactCheckV2Status.verified;
    case 'DISPUTED':
      return FactCheckV2Status.disputed;
    case 'NEEDS_MORE_INFO':
    default:
      return FactCheckV2Status.needsMoreInfo;
  }
}

class EvidenceItemV2 {
  final String source;
  final String? url;
  final String extractedQuote;
  final double relevanceScore;

  const EvidenceItemV2({
    required this.source,
    this.url,
    required this.extractedQuote,
    required this.relevanceScore,
  });

  factory EvidenceItemV2.fromJson(Map<String, dynamic> json) {
    return EvidenceItemV2(
      source: json['source'] as String,
      url: json['url'] as String?,
      extractedQuote: json['extracted_quote'] as String,
      relevanceScore: (json['relevance_score'] as num).toDouble(),
    );
  }
}

class Perspective {
  final List<String> sources;
  final String summary;

  const Perspective({required this.sources, required this.summary});

  factory Perspective.fromJson(Map<String, dynamic> json) {
    return Perspective(
      sources: (json['sources'] as List<dynamic>? ?? []).map((e) => e as String).toList(),
      summary: json['summary'] as String,
    );
  }
}

class Perspectives {
  final Perspective pro;
  final Perspective against;

  const Perspectives({required this.pro, required this.against});

  factory Perspectives.fromJson(Map<String, dynamic> json) {
    return Perspectives(
      pro: Perspective.fromJson(json['pro'] as Map<String, dynamic>),
      against: Perspective.fromJson(json['against'] as Map<String, dynamic>),
    );
  }
}

class FactCheckV2 {
  final String id;
  final String factCheckId;
  final String claim;
  final FactCheckV2Status status;
  final List<EvidenceItemV2> evidence;
  final String verdict;
  final double confidence;
  final Perspectives? perspectives;
  final DateTime createdAt;

  const FactCheckV2({
    required this.id,
    required this.factCheckId,
    required this.claim,
    required this.status,
    required this.evidence,
    required this.verdict,
    required this.confidence,
    this.perspectives,
    required this.createdAt,
  });

  factory FactCheckV2.fromJson(Map<String, dynamic> json) {
    return FactCheckV2(
      id: json['id'] as String,
      factCheckId: json['fact_check_id'] as String,
      claim: json['claim'] as String,
      status: factCheckV2StatusFromJson(json['status'] as String),
      evidence: (json['evidence'] as List<dynamic>? ?? [])
          .map((e) => EvidenceItemV2.fromJson(e as Map<String, dynamic>))
          .toList(),
      verdict: json['verdict'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      perspectives: json['perspectives'] == null
          ? null
          : Perspectives.fromJson(json['perspectives'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
