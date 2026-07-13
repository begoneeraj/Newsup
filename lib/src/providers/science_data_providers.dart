import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/data_story.dart';
import '../models/science_research.dart';
import '../services/supabase_service.dart';

final scienceResearchReportsProvider = FutureProvider<List<ScienceResearchReport>>((ref) {
  return SupabaseService.instance.fetchScienceResearchReports();
});

final dataStoriesProvider = FutureProvider<List<DataStory>>((ref) {
  return SupabaseService.instance.fetchDataStories();
});
