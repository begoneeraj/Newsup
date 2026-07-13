import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/pinned_statistic.dart';
import '../services/supabase_service.dart';

final pinnedStatisticsProvider = FutureProvider<List<PinnedStatistic>>((ref) {
  return SupabaseService.instance.fetchPinnedStatistics();
});
