import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/fact_check.dart';
import '../services/supabase_service.dart';

final factChecksProvider = FutureProvider<List<FactCheck>>((ref) {
  return SupabaseService.instance.fetchFactChecks();
});

final factCheckByIdProvider = FutureProvider.family<FactCheck?, String>((ref, id) {
  return SupabaseService.instance.fetchFactCheckById(id);
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
