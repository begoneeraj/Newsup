import '../utils/genz_fallback_translator.dart';

enum SlowCrisisCategory {
  water,
  airPollution,
  groundwater,
  healthcareCapacity,
  educationDropout,
  judiciaryDelay,
  infrastructure,
  housingAffordability,
}

extension SlowCrisisCategoryLabel on SlowCrisisCategory {
  String get label {
    switch (this) {
      case SlowCrisisCategory.water:
        return 'Water';
      case SlowCrisisCategory.airPollution:
        return 'Air Pollution';
      case SlowCrisisCategory.groundwater:
        return 'Groundwater';
      case SlowCrisisCategory.healthcareCapacity:
        return 'Healthcare Capacity';
      case SlowCrisisCategory.educationDropout:
        return 'Education Dropout';
      case SlowCrisisCategory.judiciaryDelay:
        return 'Judiciary Delay';
      case SlowCrisisCategory.infrastructure:
        return 'Infrastructure';
      case SlowCrisisCategory.housingAffordability:
        return 'Housing Affordability';
    }
  }
}

SlowCrisisCategory slowCrisisCategoryFromJson(String value) {
  switch (value) {
    case 'water':
      return SlowCrisisCategory.water;
    case 'air_pollution':
      return SlowCrisisCategory.airPollution;
    case 'groundwater':
      return SlowCrisisCategory.groundwater;
    case 'healthcare_capacity':
      return SlowCrisisCategory.healthcareCapacity;
    case 'education_dropout':
      return SlowCrisisCategory.educationDropout;
    case 'judiciary_delay':
      return SlowCrisisCategory.judiciaryDelay;
    case 'infrastructure':
      return SlowCrisisCategory.infrastructure;
    case 'housing_affordability':
    default:
      return SlowCrisisCategory.housingAffordability;
  }
}

enum SlowCrisisSeverity { stable, worsening, improving, critical }

extension SlowCrisisSeverityLabel on SlowCrisisSeverity {
  String get label {
    switch (this) {
      case SlowCrisisSeverity.stable:
        return 'Stable';
      case SlowCrisisSeverity.worsening:
        return 'Worsening';
      case SlowCrisisSeverity.improving:
        return 'Improving';
      case SlowCrisisSeverity.critical:
        return 'Critical';
    }
  }
}

SlowCrisisSeverity? slowCrisisSeverityFromJson(String? value) {
  switch (value) {
    case 'stable':
      return SlowCrisisSeverity.stable;
    case 'worsening':
      return SlowCrisisSeverity.worsening;
    case 'improving':
      return SlowCrisisSeverity.improving;
    case 'critical':
      return SlowCrisisSeverity.critical;
    default:
      return null;
  }
}

class CrisisDataPoint {
  final String id;
  final double value;
  final String unit;
  final String recordedDate;
  final String sourceUrl;
  final String? note;

  const CrisisDataPoint({
    required this.id,
    required this.value,
    required this.unit,
    required this.recordedDate,
    required this.sourceUrl,
    this.note,
  });

  factory CrisisDataPoint.fromJson(Map<String, dynamic> json) {
    return CrisisDataPoint(
      id: json['id'] as String,
      value: (json['value'] as num).toDouble(),
      unit: json['unit'] as String,
      recordedDate: json['recorded_date'] as String,
      sourceUrl: json['source_url'] as String? ?? '',
      note: json['note'] as String?,
    );
  }
}

class CrisisNarrativeUpdate {
  final String id;
  final String narrative;
  final String? genzNarrative;
  final String sourceUrl;
  final DateTime generatedAt;

  const CrisisNarrativeUpdate({
    required this.id,
    required this.narrative,
    this.genzNarrative,
    required this.sourceUrl,
    required this.generatedAt,
  });

  String display(bool genzVoice) => genzVoice ? (genzNarrative ?? genzFallbackTranslate(narrative)) : narrative;

  factory CrisisNarrativeUpdate.fromJson(Map<String, dynamic> json) {
    return CrisisNarrativeUpdate(
      id: json['id'] as String,
      narrative: json['narrative'] as String,
      genzNarrative: json['genz_narrative'] as String?,
      sourceUrl: json['source_url'] as String? ?? '',
      generatedAt: DateTime.parse(json['generated_at'] as String),
    );
  }
}

class SlowCrisis {
  final String id;
  final String crisisSlug;
  final String title;
  final SlowCrisisCategory category;
  final String? region;
  final String? description;
  final String? genzDescription;
  final SlowCrisisSeverity? currentSeverity;
  final DateTime? lastComputedAt;
  final String? dataSource;

  const SlowCrisis({
    required this.id,
    required this.crisisSlug,
    required this.title,
    required this.category,
    this.region,
    this.description,
    this.genzDescription,
    this.currentSeverity,
    this.lastComputedAt,
    this.dataSource,
  });

  String? displayDescription(bool genzVoice) {
    if (description == null) return null;
    return genzVoice ? (genzDescription ?? genzFallbackTranslate(description!)) : description;
  }

  factory SlowCrisis.fromJson(Map<String, dynamic> json) {
    return SlowCrisis(
      id: json['id'] as String,
      crisisSlug: json['crisis_slug'] as String,
      title: json['title'] as String,
      category: slowCrisisCategoryFromJson(json['category'] as String),
      region: json['region'] as String?,
      description: json['description'] as String?,
      genzDescription: json['genz_description'] as String?,
      currentSeverity: slowCrisisSeverityFromJson(json['current_severity'] as String?),
      lastComputedAt:
          json['last_computed_at'] == null ? null : DateTime.parse(json['last_computed_at'] as String),
      dataSource: json['data_source'] as String?,
    );
  }
}
