import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/govt_promise.dart';
import '../services/supabase_service.dart';

final govtPromisesProvider = FutureProvider<List<GovtPromise>>((ref) {
  return SupabaseService.instance.fetchGovtPromises();
});

final govtPromiseByIdProvider = FutureProvider.family<GovtPromise?, String>((ref, id) {
  return SupabaseService.instance.fetchGovtPromiseById(id);
});

final promiseEvidenceProvider = FutureProvider.family<List<PromiseEvidence>, String>((ref, promiseId) {
  return SupabaseService.instance.fetchPromiseEvidence(promiseId);
});

/// All fields null/empty means "no filter applied".
class GovtPromiseFilter {
  final GovtPromiseCategory? category;
  final GovtPromiseStatus? status;
  final GovtPromiseImplementationQuality? implementationQuality;
  final String? party;
  final int? electionYear;

  const GovtPromiseFilter({
    this.category,
    this.status,
    this.implementationQuality,
    this.party,
    this.electionYear,
  });

  GovtPromiseFilter copyWith({
    GovtPromiseCategory? Function()? category,
    GovtPromiseStatus? Function()? status,
    GovtPromiseImplementationQuality? Function()? implementationQuality,
    String? Function()? party,
    int? Function()? electionYear,
  }) {
    return GovtPromiseFilter(
      category: category != null ? category() : this.category,
      status: status != null ? status() : this.status,
      implementationQuality:
          implementationQuality != null ? implementationQuality() : this.implementationQuality,
      party: party != null ? party() : this.party,
      electionYear: electionYear != null ? electionYear() : this.electionYear,
    );
  }

  bool matches(GovtPromise promise) {
    if (category != null && promise.category != category) return false;
    if (status != null && promise.currentStatus != status) return false;
    if (implementationQuality != null && promise.implementationQuality != implementationQuality) {
      return false;
    }
    if (party != null && promise.party != party) return false;
    if (electionYear != null && promise.electionYear != electionYear) return false;
    return true;
  }
}

final govtPromiseFilterProvider = StateProvider<GovtPromiseFilter>((ref) => const GovtPromiseFilter());

final filteredGovtPromisesProvider = Provider<AsyncValue<List<GovtPromise>>>((ref) {
  final asyncPromises = ref.watch(govtPromisesProvider);
  final filter = ref.watch(govtPromiseFilterProvider);
  return asyncPromises.whenData(
    (promises) => promises.where(filter.matches).toList(),
  );
});
