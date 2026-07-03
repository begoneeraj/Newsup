import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../models/news_headline.dart';
import '../models/news_source.dart';

/// Read-only RSS headline fetcher, used for reference/cross-checking only.
///
/// This does NOT generate FactCheck or CrisisReport entries — those remain
/// manually curated in `mock_data.dart` for now.
class RssService {
  RssService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const List<NewsSource> feeds = [
    NewsSource(
      // TODO: PIB RSS feeds are per-ministry, e.g.
      // https://pib.gov.in/RssMain.aspx?ModId=6&Lang=1&Regid=3 (varies by ministry).
      // Pick the relevant ministry feed(s) once scope is decided.
      feedUrl: 'https://pib.gov.in',
      sourceName: 'PIB India',
      category: NewsSourceCategory.official,
    ),
    NewsSource(
      feedUrl: 'https://www.thehindu.com/news/national/feeder/default.rss',
      sourceName: 'The Hindu',
      category: NewsSourceCategory.media,
    ),
    NewsSource(
      feedUrl: 'https://indianexpress.com/section/india/feed/',
      sourceName: 'Indian Express',
      category: NewsSourceCategory.media,
    ),
  ];

  Future<List<NewsHeadline>> fetchAllHeadlines() async {
    final results = await Future.wait(
      feeds.map((feed) => _fetchFeed(feed).catchError((_) => <NewsHeadline>[])),
    );
    final headlines = results.expand((h) => h).toList();
    headlines.sort((a, b) {
      if (a.pubDate == null || b.pubDate == null) return 0;
      return b.pubDate!.compareTo(a.pubDate!);
    });
    return headlines;
  }

  Future<List<NewsHeadline>> _fetchFeed(NewsSource feed) async {
    final response = await _client.get(Uri.parse(feed.feedUrl));
    if (response.statusCode != 200) {
      return const [];
    }

    final document = XmlDocument.parse(response.body);
    final items = document.findAllElements('item');

    return items.map((item) {
      final title = item.getElement('title')?.innerText.trim() ?? '';
      final link = item.getElement('link')?.innerText.trim() ?? '';
      final pubDateText = item.getElement('pubDate')?.innerText.trim();
      DateTime? pubDate;
      if (pubDateText != null) {
        try {
          pubDate = HttpDate.parse(pubDateText);
        } catch (_) {
          pubDate = DateTime.tryParse(pubDateText);
        }
      }
      return NewsHeadline(
        title: title,
        link: link,
        pubDate: pubDate,
        source: feed.sourceName,
      );
    }).toList();
  }

  void dispose() => _client.close();
}

/// Minimal RFC 1123 date parser for RSS `pubDate` fields, avoiding a
/// dependency on `dart:io`'s HttpDate (not available on web).
class HttpDate {
  static final _months = {
    'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
    'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
  };

  /// Parses formats like "Wed, 03 Jul 2026 10:00:00 GMT" or "+0530".
  static DateTime parse(String input) {
    final parts = input.trim().split(RegExp(r'\s+'));
    // Expect: [Weekday,] dd Mon yyyy HH:mm:ss (+zzzz|GMT|...)
    final offset = parts.length > 1 && RegExp(r'^[A-Za-z]{3},?$').hasMatch(parts[0])
        ? 1
        : 0;
    final day = int.parse(parts[offset]);
    final month = _months[parts[offset + 1]]!;
    final year = int.parse(parts[offset + 2]);
    final timeParts = parts[offset + 3].split(':');
    final hour = int.parse(timeParts[0]);
    final minute = int.parse(timeParts[1]);
    final second = int.parse(timeParts[2]);
    return DateTime.utc(year, month, day, hour, minute, second);
  }
}
