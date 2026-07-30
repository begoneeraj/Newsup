import 'dart:math' as math;

/// Matches the `underreported_topics` row shape directly (see
/// supabase/migrations/0015_underreported_topics.sql,
/// 0016_underreported_topic_narratives.sql) -- SupabaseService queries this
/// table straight, same pattern as every other feature in this app, not
/// through src/api_server.py's /underreported-topics endpoint.
class UnderreportedTopic {
  final String id;
  final String topicSlug;
  final String title;
  final String? dataSource;
  final double? gapScore;
  final int? nicheCount;
  final int? mainstreamCount;
  final DateTime? lastComputedAt;
  final String? narrativeSummary;
  final String? genzSummary;

  UnderreportedTopic({
    required this.id,
    required this.topicSlug,
    required this.title,
    this.dataSource,
    this.gapScore,
    this.nicheCount,
    this.mainstreamCount,
    this.lastComputedAt,
    this.narrativeSummary,
    this.genzSummary,
  });

  factory UnderreportedTopic.fromJson(Map<String, dynamic> json) {
    return UnderreportedTopic(
      id: json['id'] as String,
      topicSlug: json['topic_slug'] as String,
      title: json['title'] as String,
      dataSource: json['data_source'] as String?,
      gapScore: (json['current_gap_score'] as num?)?.toDouble(),
      nicheCount: json['current_niche_count'] as int?,
      mainstreamCount: json['current_mainstream_count'] as int?,
      lastComputedAt: json['last_computed_at'] != null
          ? DateTime.parse(json['last_computed_at'] as String)
          : null,
      narrativeSummary: json['latest_narrative_summary'] as String?,
      genzSummary: json['latest_narrative_genz_summary'] as String?,
    );
  }

  /// gap_score is log2((niche+1)/(mainstream+1)) (see
  /// pipeline.underreported_topics._compute_gap_score) -- unbounded, not a
  /// 0-1 percentage. A score of 0 means official/niche and mainstream
  /// coverage are roughly equal; +1 means niche coverage is ~2x mainstream;
  /// +2 means ~4x, etc. This renders that as a "fold gap" instead of the
  /// nonsensical raw-percentage label the UI used to show.
  String get gapScoreLabel {
    final score = gapScore;
    if (score == null) return '';
    if (score <= 0) return 'Well covered';
    final fold = math.pow(2, score);
    return '${fold.toStringAsFixed(1)}x gap';
  }
}

/// One row of `underreported_topic_points` -- a single day's niche vs.
/// mainstream counts and the resulting gap_score for one topic.
class UnderreportedTopicPoint {
  final String recordedDate;
  final int nicheCount;
  final int mainstreamCount;
  final int hindiMainstreamCount;
  final int tamilMainstreamCount;
  final double gapScore;
  final List<String> states;
  final List<SourceLink> exampleNicheSources;
  final List<SourceLink> exampleMainstreamSources;

  UnderreportedTopicPoint({
    required this.recordedDate,
    required this.nicheCount,
    required this.mainstreamCount,
    required this.hindiMainstreamCount,
    required this.tamilMainstreamCount,
    required this.gapScore,
    required this.states,
    required this.exampleNicheSources,
    required this.exampleMainstreamSources,
  });

  factory UnderreportedTopicPoint.fromJson(Map<String, dynamic> json) {
    return UnderreportedTopicPoint(
      recordedDate: json['recorded_date'] as String,
      nicheCount: json['niche_count'] as int,
      mainstreamCount: json['mainstream_count'] as int,
      hindiMainstreamCount: json['hindi_mainstream_count'] as int? ?? 0,
      tamilMainstreamCount: json['tamil_mainstream_count'] as int? ?? 0,
      gapScore: (json['gap_score'] as num).toDouble(),
      states: (json['states'] as List<dynamic>? ?? []).cast<String>(),
      exampleNicheSources: (json['example_niche_sources'] as List<dynamic>? ?? [])
          .map((e) => SourceLink.fromJson(e as Map<String, dynamic>))
          .toList(),
      exampleMainstreamSources: (json['example_mainstream_sources'] as List<dynamic>? ?? [])
          .map((e) => SourceLink.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class SourceLink {
  final String title;
  final String url;
  final String? source;

  SourceLink({required this.title, required this.url, this.source});

  factory SourceLink.fromJson(Map<String, dynamic> json) {
    return SourceLink(
      title: json['title'] as String,
      url: json['url'] as String? ?? '',
      source: json['source'] as String?,
    );
  }
}
