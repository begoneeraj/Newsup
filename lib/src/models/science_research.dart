import '../utils/genz_fallback_translator.dart';

enum ScienceField { space, biology, physics, chemistry, environment, medicine, materials, other }

extension ScienceFieldLabel on ScienceField {
  String get label {
    switch (this) {
      case ScienceField.space:
        return 'Space';
      case ScienceField.biology:
        return 'Biology';
      case ScienceField.physics:
        return 'Physics';
      case ScienceField.chemistry:
        return 'Chemistry';
      case ScienceField.environment:
        return 'Environment';
      case ScienceField.medicine:
        return 'Medicine';
      case ScienceField.materials:
        return 'Materials';
      case ScienceField.other:
        return 'Other';
    }
  }
}

ScienceField scienceFieldFromJson(String value) {
  switch (value) {
    case 'space':
      return ScienceField.space;
    case 'biology':
      return ScienceField.biology;
    case 'physics':
      return ScienceField.physics;
    case 'chemistry':
      return ScienceField.chemistry;
    case 'environment':
      return ScienceField.environment;
    case 'medicine':
      return ScienceField.medicine;
    case 'materials':
      return ScienceField.materials;
    case 'other':
    default:
      return ScienceField.other;
  }
}

class ScienceResearchReport {
  final String id;
  final ScienceField field;
  final String? institution;
  final bool indiaRelevance;
  final String? whatThisMeans;
  final String headlinePlain;
  final String? genzSummary;
  final List<String> keyFacts;
  final String sourceUrl;
  final DateTime processedAt;

  const ScienceResearchReport({
    required this.id,
    required this.field,
    this.institution,
    this.indiaRelevance = false,
    this.whatThisMeans,
    required this.headlinePlain,
    this.genzSummary,
    this.keyFacts = const [],
    required this.sourceUrl,
    required this.processedAt,
  });

  String displaySummary(bool genzVoice) =>
      genzVoice ? (genzSummary ?? genzFallbackTranslate(headlinePlain)) : headlinePlain;

  factory ScienceResearchReport.fromJson(Map<String, dynamic> json) {
    return ScienceResearchReport(
      id: json['id'] as String,
      field: scienceFieldFromJson(json['field'] as String),
      institution: json['institution'] as String?,
      indiaRelevance: json['india_relevance'] as bool? ?? false,
      whatThisMeans: json['what_this_means'] as String?,
      headlinePlain: json['headline_plain'] as String,
      genzSummary: json['genz_summary'] as String?,
      keyFacts: (json['key_facts'] as List<dynamic>? ?? []).map((e) => e as String).toList(),
      sourceUrl: json['source_url'] as String? ?? '',
      processedAt: DateTime.parse(json['processed_at'] as String),
    );
  }
}
