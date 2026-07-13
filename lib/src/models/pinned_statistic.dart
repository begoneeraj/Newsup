/// Mirrors the `pinned_statistics` table (see
/// supabase/migrations/0011_crisis_expansion.sql) — a small, manually
/// curated set of headline national stats (e.g. NCRB figures), distinct
/// from the `statistics` table which is an unranked dump of whatever the
/// pipeline's Groq stats extractor pulls from article text at ingest time.
class PinnedStatistic {
  final String id;
  final String label;
  final num value;
  final String? unit;
  final int year;
  final String source;
  final String? sourceUrl;
  final String category;

  const PinnedStatistic({
    required this.id,
    required this.label,
    required this.value,
    this.unit,
    required this.year,
    required this.source,
    this.sourceUrl,
    required this.category,
  });

  factory PinnedStatistic.fromJson(Map<String, dynamic> json) {
    return PinnedStatistic(
      id: json['id'] as String,
      label: json['label'] as String,
      value: json['value'] as num,
      unit: json['unit'] as String?,
      year: json['year'] as int,
      source: json['source'] as String,
      sourceUrl: json['source_url'] as String?,
      category: json['category'] as String,
    );
  }
}
