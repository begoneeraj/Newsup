import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/coverage.dart';
import '../models/fact_check.dart';
import '../models/fact_check_v2.dart';
import '../services/supabase_service.dart';

final factChecksProvider = FutureProvider<List<FactCheck>>((ref) {
  return SupabaseService.instance.fetchFactChecks();
});

final factCheckByIdProvider = FutureProvider.family<FactCheck?, String>((ref, id) {
  return SupabaseService.instance.fetchFactCheckById(id);
});

final outletSourcesProvider = FutureProvider.family<List<OutletSource>, String>((ref, factCheckId) {
  return SupabaseService.instance.fetchOutletSources(factCheckId);
});

final coverageAnalysisProvider = FutureProvider.family<CoverageAnalysis?, String>((ref, factCheckId) {
  return SupabaseService.instance.fetchCoverageAnalysis(factCheckId);
});

final factCheckV2Provider = FutureProvider.family<FactCheckV2?, String>((ref, factCheckId) {
  return SupabaseService.instance.fetchFactCheckV2(factCheckId);
});

/// Null means "All" filter.
final factCheckFilterProvider = StateProvider<FactCheckStatus?>((ref) => null);

final filteredFactChecksProvider = Provider<AsyncValue<List<FactCheck>>>((ref) {
  final asyncFactChecks = ref.watch(factChecksProvider);
  final filter = ref.watch(factCheckFilterProvider);
  return asyncFactChecks.whenData((factChecks) {
    if (filter == null) return factChecks;
    return factChecks.where((fc) => fc.status == filter).toList();
  });
});
