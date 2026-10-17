import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum NewsSourceFilter { all, newsApi, gdelt }

final liveArticlesProvider = StreamProvider.autoDispose
    .family<List<Map<String, dynamic>>, NewsSourceFilter>((ref, filter) {
  Query<Map<String, dynamic>> query =
      FirebaseFirestore.instance.collection('raw_articles');
  if (filter != NewsSourceFilter.all) {
    query = query.where('source_system',
        isEqualTo: filter == NewsSourceFilter.newsApi ? 'newsapi' : 'gdelt');
  }
  return query
      .orderBy('published_at', descending: true)
      .limit(50)
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
});
