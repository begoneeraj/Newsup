import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/news_headline.dart';
import '../services/rss_service.dart';

final rssServiceProvider = Provider<RssService>((ref) {
  final service = RssService();
  ref.onDispose(service.dispose);
  return service;
});

final newsHeadlinesProvider = FutureProvider<List<NewsHeadline>>((ref) async {
  final service = ref.watch(rssServiceProvider);
  return service.fetchAllHeadlines();
});
