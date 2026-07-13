import '../utils/genz_fallback_translator.dart';

class DataStoryChartPoint {
  final String date;
  final double value;

  const DataStoryChartPoint({required this.date, required this.value});

  factory DataStoryChartPoint.fromJson(Map<String, dynamic> json) {
    return DataStoryChartPoint(
      date: json['date'] as String,
      value: (json['value'] as num).toDouble(),
    );
  }
}

class DataStory {
  final String id;
  final String? slug;
  final String title;
  final String? genzTitle;
  final String datasetSource;
  final String? headlineStat;
  final String narrativeSummary;
  final String? genzSummary;
  final List<DataStoryChartPoint> chartData;
  final DateTime publishedAt;

  const DataStory({
    required this.id,
    this.slug,
    required this.title,
    this.genzTitle,
    required this.datasetSource,
    this.headlineStat,
    required this.narrativeSummary,
    this.genzSummary,
    this.chartData = const [],
    required this.publishedAt,
  });

  String displayTitle(bool genzVoice) => genzVoice ? (genzTitle ?? genzFallbackTranslate(title)) : title;

  String displaySummary(bool genzVoice) =>
      genzVoice ? (genzSummary ?? genzFallbackTranslate(narrativeSummary)) : narrativeSummary;

  factory DataStory.fromJson(Map<String, dynamic> json) {
    return DataStory(
      id: json['id'] as String,
      slug: json['slug'] as String?,
      title: json['title'] as String,
      genzTitle: json['genz_title'] as String?,
      datasetSource: json['dataset_source'] as String,
      headlineStat: json['headline_stat'] as String?,
      narrativeSummary: json['narrative_summary'] as String,
      genzSummary: json['genz_summary'] as String?,
      chartData: (json['chart_data'] as List<dynamic>? ?? [])
          .map((e) => DataStoryChartPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      publishedAt: DateTime.parse(json['published_at'] as String),
    );
  }
}
