enum NewsSourceCategory { official, media }

class NewsSource {
  final String feedUrl;
  final String sourceName;
  final NewsSourceCategory category;

  const NewsSource({
    required this.feedUrl,
    required this.sourceName,
    required this.category,
  });
}
