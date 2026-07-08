enum FactCheckStatus {
  verified,
  falseClaim,
  misleading,
  partlyTrue,
  outOfContext,
  satire,
  unverified,
}

extension FactCheckStatusLabel on FactCheckStatus {
  String get label {
    switch (this) {
      case FactCheckStatus.verified:
        return 'Verified';
      case FactCheckStatus.falseClaim:
        return 'False';
      case FactCheckStatus.misleading:
        return 'Misleading';
      case FactCheckStatus.partlyTrue:
        return 'Partly True';
      case FactCheckStatus.outOfContext:
        return 'Out of Context';
      case FactCheckStatus.satire:
        return 'Satire';
      case FactCheckStatus.unverified:
        return 'Unverified';
    }
  }
}

extension FactCheckStatusGenzLabel on FactCheckStatus {
  /// Punchier, lowercase Genz-voice variant of [label].
  String get genzLabel {
    switch (this) {
      case FactCheckStatus.verified:
        return 'checks out';
      case FactCheckStatus.falseClaim:
        return 'nope, false';
      case FactCheckStatus.misleading:
        return 'kinda misleading';
      case FactCheckStatus.partlyTrue:
        return 'half right';
      case FactCheckStatus.outOfContext:
        return 'missing context';
      case FactCheckStatus.satire:
        return "it's a joke";
      case FactCheckStatus.unverified:
        return "jury's out";
    }
  }
}

extension FactCheckStatusGuessing on FactCheckStatus {
  /// Emoji + label badge used in the Reality Feed swipe deck.
  String get genzBadgeLabel {
    switch (this) {
      case FactCheckStatus.verified:
        return '✔ Checks Out';
      case FactCheckStatus.falseClaim:
        return '🧢 Cap';
      case FactCheckStatus.misleading:
        return '🤨 Sus';
      case FactCheckStatus.partlyTrue:
        return '🌗 Half Baked';
      case FactCheckStatus.outOfContext:
        return '🎬 No Context';
      case FactCheckStatus.satire:
        return '🎭 Bit';
      case FactCheckStatus.unverified:
        return "❓ Jury's Out";
    }
  }

  /// Whether a right-swipe ("this is true") guess counts as correct.
  /// Null means the claim can't be graded yet (unverified).
  bool? get countsAsTrueForGuessing {
    switch (this) {
      case FactCheckStatus.verified:
      case FactCheckStatus.partlyTrue:
        return true;
      case FactCheckStatus.falseClaim:
      case FactCheckStatus.misleading:
      case FactCheckStatus.outOfContext:
      case FactCheckStatus.satire:
        return false;
      case FactCheckStatus.unverified:
        return null;
    }
  }
}

enum SourceReliability { high, med, low }

extension SourceReliabilityLabel on SourceReliability {
  String get label {
    switch (this) {
      case SourceReliability.high:
        return 'High';
      case SourceReliability.med:
        return 'Medium';
      case SourceReliability.low:
        return 'Low';
    }
  }
}

class SourceRef {
  final String title;
  final String url;
  final DateTime publishedAt;

  const SourceRef({
    required this.title,
    required this.url,
    required this.publishedAt,
  });

  factory SourceRef.fromJson(Map<String, dynamic> json) {
    return SourceRef(
      title: json['title'] as String,
      url: json['url'] as String,
      publishedAt: DateTime.parse(json['published_at'] as String),
    );
  }
}

/// Parses the UPPER_SNAKE_CASE status strings written by the ingestion
/// pipeline (see src/models/schemas.py::FactCheckStatus).
FactCheckStatus factCheckStatusFromJson(String value) {
  switch (value) {
    case 'VERIFIED':
      return FactCheckStatus.verified;
    case 'FALSE':
      return FactCheckStatus.falseClaim;
    case 'MISLEADING':
      return FactCheckStatus.misleading;
    case 'PARTLY_TRUE':
      return FactCheckStatus.partlyTrue;
    case 'OUT_OF_CONTEXT':
      return FactCheckStatus.outOfContext;
    case 'SATIRE':
      return FactCheckStatus.satire;
    case 'UNVERIFIED':
    default:
      return FactCheckStatus.unverified;
  }
}

SourceReliability sourceReliabilityFromJson(String value) {
  switch (value) {
    case 'HIGH':
      return SourceReliability.high;
    case 'MED':
      return SourceReliability.med;
    case 'LOW':
    default:
      return SourceReliability.low;
  }
}

class FactCheck {
  final String id;
  final String claimText;
  final String origin;
  final FactCheckStatus status;
  final int evidenceConfidence;
  final SourceReliability sourceReliability;
  final int independentConfirmations;
  final bool officialConfirmation;
  final List<SourceRef> sources;
  final String? expertAnalysis;
  final DateTime createdAt;

  /// Optional shorter, punchier rephrase of [claimText] for Genz voice.
  /// Falls back to [claimText] when null.
  final String? genzSummary;

  const FactCheck({
    required this.id,
    required this.claimText,
    required this.origin,
    required this.status,
    required this.evidenceConfidence,
    required this.sourceReliability,
    required this.independentConfirmations,
    required this.officialConfirmation,
    required this.sources,
    this.expertAnalysis,
    required this.createdAt,
    this.genzSummary,
  });

  String displayClaim(bool genzVoice) =>
      genzVoice ? (genzSummary ?? claimText) : claimText;

  factory FactCheck.fromJson(Map<String, dynamic> json) {
    return FactCheck(
      id: json['id'] as String,
      claimText: json['claim_text'] as String,
      origin: json['origin'] as String,
      status: factCheckStatusFromJson(json['status'] as String),
      evidenceConfidence: json['evidence_confidence'] as int,
      sourceReliability: sourceReliabilityFromJson(json['source_reliability'] as String),
      independentConfirmations: json['independent_confirmations'] as int,
      officialConfirmation: json['official_confirmation'] as bool,
      sources: (json['sources'] as List<dynamic>? ?? [])
          .map((e) => SourceRef.fromJson(e as Map<String, dynamic>))
          .toList(),
      expertAnalysis: json['expert_analysis'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      genzSummary: json['genz_summary'] as String?,
    );
  }
}
