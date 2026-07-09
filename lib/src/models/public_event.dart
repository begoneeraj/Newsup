import 'crisis_report.dart' show TimelineEvent;

/// Mirrors src/models/schemas.py::PublicEventType. Deliberately a trimmed
/// subset — see supabase/migrations/0009_public_events.sql.
enum PublicEventType {
  examLeak,
  studentSuicide,
  genderViolence,
  weatherDisaster,
  earthquake,
  aiTech,
  examDelay,
  otherCrisis,
  courtCase,
  governmentPolicy,
  economy,
  crime,
  technology,
  misc,
}

extension PublicEventTypeLabel on PublicEventType {
  String get label {
    switch (this) {
      case PublicEventType.examLeak:
        return 'Exam Leak';
      case PublicEventType.studentSuicide:
        return 'Student Suicide';
      case PublicEventType.genderViolence:
        return 'Gender Violence';
      case PublicEventType.weatherDisaster:
        return 'Weather Disaster';
      case PublicEventType.earthquake:
        return 'Earthquake';
      case PublicEventType.aiTech:
        return 'AI / Tech';
      case PublicEventType.examDelay:
        return 'Exam Delay';
      case PublicEventType.otherCrisis:
        return 'Crisis';
      case PublicEventType.courtCase:
        return 'Court Case';
      case PublicEventType.governmentPolicy:
        return 'Government Policy';
      case PublicEventType.economy:
        return 'Economy';
      case PublicEventType.crime:
        return 'Crime';
      case PublicEventType.technology:
        return 'Technology';
      case PublicEventType.misc:
        return 'General';
    }
  }
}

PublicEventType publicEventTypeFromJson(String value) {
  switch (value) {
    case 'exam_leak':
      return PublicEventType.examLeak;
    case 'student_suicide':
      return PublicEventType.studentSuicide;
    case 'gender_violence':
      return PublicEventType.genderViolence;
    case 'weather_disaster':
      return PublicEventType.weatherDisaster;
    case 'earthquake':
      return PublicEventType.earthquake;
    case 'ai_tech':
      return PublicEventType.aiTech;
    case 'exam_delay':
      return PublicEventType.examDelay;
    case 'court_case':
      return PublicEventType.courtCase;
    case 'government_policy':
      return PublicEventType.governmentPolicy;
    case 'economy':
      return PublicEventType.economy;
    case 'crime':
      return PublicEventType.crime;
    case 'technology':
      return PublicEventType.technology;
    case 'other_crisis':
      return PublicEventType.otherCrisis;
    case 'misc':
    default:
      return PublicEventType.misc;
  }
}

enum PublicEventSeverity { low, medium, high }

PublicEventSeverity? publicEventSeverityFromJson(String? value) {
  switch (value) {
    case 'low':
      return PublicEventSeverity.low;
    case 'medium':
      return PublicEventSeverity.medium;
    case 'high':
      return PublicEventSeverity.high;
    default:
      return null;
  }
}

enum PublicEventStatus { ongoing, resolved, developing }

extension PublicEventStatusLabel on PublicEventStatus {
  String get label {
    switch (this) {
      case PublicEventStatus.ongoing:
        return 'Ongoing';
      case PublicEventStatus.resolved:
        return 'Resolved';
      case PublicEventStatus.developing:
        return 'Developing';
    }
  }
}

PublicEventStatus? publicEventStatusFromJson(String? value) {
  switch (value) {
    case 'ongoing':
      return PublicEventStatus.ongoing;
    case 'resolved':
      return PublicEventStatus.resolved;
    case 'developing':
      return PublicEventStatus.developing;
    default:
      return null;
  }
}

/// One entry in official_sources/media_sources/reddit_sources/youtube_sources
/// — same {title,url,published_at} shape the pipeline writes for all four.
class PublicEventSource {
  final String title;
  final String url;
  final DateTime? publishedAt;

  const PublicEventSource({required this.title, required this.url, this.publishedAt});

  factory PublicEventSource.fromJson(Map<String, dynamic> json) {
    return PublicEventSource(
      title: json['title'] as String? ?? '',
      url: json['url'] as String? ?? '',
      publishedAt: json['published_at'] != null ? DateTime.tryParse(json['published_at'] as String) : null,
    );
  }
}

List<PublicEventSource> _sourcesFromJson(dynamic value) {
  return (value as List<dynamic>? ?? [])
      .map((e) => PublicEventSource.fromJson(e as Map<String, dynamic>))
      .toList();
}

/// Mirrors src/models/schemas.py::PublicEventSchema — see
/// supabase/migrations/0009_public_events.sql. Dual-written from
/// fact_checks/crisis_reports/crises, so this is the broad, always-populated
/// feed (unlike CrisisReport, which only ever comes from the Reddit-sourced
/// crisis-hunting fetcher and can be structurally empty if that source is
/// blocked/quiet).
class PublicEvent {
  final String id;
  final String title;
  final String summary;
  final PublicEventType eventType;
  final int? importanceScore;
  final PublicEventSeverity? severity;
  final PublicEventStatus? status;

  final String country;
  final String? state;
  final String? city;

  final DateTime? startDate;
  final DateTime lastUpdated;

  final List<PublicEventSource> officialSources;
  final List<PublicEventSource> mediaSources;
  final List<PublicEventSource> redditSources;
  final List<PublicEventSource> youtubeSources;

  final List<TimelineEvent> timeline;
  final List<String> tags;

  final String sourceTable;
  final String sourceUrl;

  const PublicEvent({
    required this.id,
    required this.title,
    required this.summary,
    required this.eventType,
    this.importanceScore,
    this.severity,
    this.status,
    required this.country,
    this.state,
    this.city,
    this.startDate,
    required this.lastUpdated,
    required this.officialSources,
    required this.mediaSources,
    required this.redditSources,
    required this.youtubeSources,
    required this.timeline,
    required this.tags,
    required this.sourceTable,
    required this.sourceUrl,
  });

  /// Total distinct outlets/sources covering this event, across every
  /// bucket — used as the "N sources" line on the card.
  int get totalSources =>
      officialSources.length + mediaSources.length + redditSources.length + youtubeSources.length;

  factory PublicEvent.fromJson(Map<String, dynamic> json) {
    return PublicEvent(
      id: json['id'] as String,
      title: json['title'] as String,
      summary: json['summary'] as String,
      eventType: publicEventTypeFromJson(json['event_type'] as String),
      importanceScore: json['importance_score'] as int?,
      severity: publicEventSeverityFromJson(json['severity'] as String?),
      status: publicEventStatusFromJson(json['status'] as String?),
      country: json['country'] as String? ?? 'India',
      state: json['state'] as String?,
      city: json['city'] as String?,
      startDate: json['start_date'] != null ? DateTime.tryParse(json['start_date'] as String) : null,
      lastUpdated: DateTime.parse(json['last_updated'] as String),
      officialSources: _sourcesFromJson(json['official_sources']),
      mediaSources: _sourcesFromJson(json['media_sources']),
      redditSources: _sourcesFromJson(json['reddit_sources']),
      youtubeSources: _sourcesFromJson(json['youtube_sources']),
      timeline: (json['timeline'] as List<dynamic>? ?? [])
          .map((e) => TimelineEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
      tags: (json['tags'] as List<dynamic>? ?? []).map((e) => e as String).toList(),
      sourceTable: json['source_table'] as String? ?? '',
      sourceUrl: json['source_url'] as String? ?? '',
    );
  }
}
