/// One year's figure from `suicide_stats_history` (see
/// supabase/migrations/0019_suicide_stats_history.sql) — a 5-year NCRB ADSI
/// series shown only on the tucked-away National Data screen, never pinned
/// to a main feed.
class SuicideStatYear {
  final String category;
  final int year;
  final int value;
  final String source;
  final String? sourceUrl;

  const SuicideStatYear({
    required this.category,
    required this.year,
    required this.value,
    required this.source,
    this.sourceUrl,
  });

  factory SuicideStatYear.fromJson(Map<String, dynamic> json) {
    return SuicideStatYear(
      category: json['category'] as String,
      year: json['year'] as int,
      value: json['value'] as int,
      source: json['source'] as String,
      sourceUrl: json['source_url'] as String?,
    );
  }
}
