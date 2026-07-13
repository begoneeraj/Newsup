import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/slow_crisis.dart';
import '../services/supabase_service.dart';

final slowCrisesProvider = FutureProvider<List<SlowCrisis>>((ref) {
  return SupabaseService.instance.fetchSlowCrises();
});

final slowCrisisByIdProvider = FutureProvider.family<SlowCrisis?, String>((ref, id) {
  return SupabaseService.instance.fetchSlowCrisisById(id);
});

final crisisDataPointsProvider = FutureProvider.family<List<CrisisDataPoint>, String>((ref, crisisId) {
  return SupabaseService.instance.fetchCrisisDataPoints(crisisId);
});

final crisisNarrativeUpdatesProvider = FutureProvider.family<List<CrisisNarrativeUpdate>, String>((ref, crisisId) {
  return SupabaseService.instance.fetchCrisisNarrativeUpdates(crisisId);
});
