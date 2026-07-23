import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/suicide_stat_year.dart';
import '../services/supabase_service.dart';

final suicideStatsHistoryProvider = FutureProvider<List<SuicideStatYear>>((ref) {
  return SupabaseService.instance.fetchSuicideStatsHistory();
});
