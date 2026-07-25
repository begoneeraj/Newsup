import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/underreported_topic.dart';
import '../services/supabase_service.dart';

final underreportedTopicsProvider = FutureProvider<List<UnderreportedTopic>>((ref) {
  return SupabaseService.instance.fetchUnderreportedTopics();
});

final underreportedTopicPointsProvider =
    FutureProvider.family<List<UnderreportedTopicPoint>, String>((ref, topicId) {
  return SupabaseService.instance.fetchUnderreportedTopicPoints(topicId);
});
