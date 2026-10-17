import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/coverage.dart';
import '../models/fact_check.dart';
import '../models/fact_check_v2.dart';
import '../services/supabase_service.dart';
import 'bookmark_provider.dart';

final savedFactChecksProvider = FutureProvider<List<FactCheck>>((ref) {
  return SupabaseService.instance
      .fetchFactChecksByIds(ref.watch(bookmarksProvider));
});

final factCheckPageLoaderProvider =
    Provider<Future<List<FactCheck>> Function(int, int)>((ref) {
  return (offset, limit) =>
      SupabaseService.instance.fetchFactChecks(offset: offset, limit: limit);
});

final factChecksProvider =
    AsyncNotifierProvider<FactChecksNotifier, List<FactCheck>>(
        FactChecksNotifier.new);

class FactChecksNotifier extends AsyncNotifier<List<FactCheck>> {
  static const pageSize = 100;
  bool loadingMore = false;
  bool hasMore = true;
  String? pageError;
  int _offset = 0;
  int _generation = 0;

  @override
  Future<List<FactCheck>> build() async {
    final generation = ++_generation;
    ref.onDispose(() => _generation++);
    loadingMore = false;
    pageError = null;
    final page = await ref.read(factCheckPageLoaderProvider)(0, pageSize);
    if (generation == _generation) {
      _offset = page.length;
      hasMore = page.length == pageSize;
    }
    return page;
  }

  Future<void> loadMore() async {
    if (loadingMore || !hasMore || !state.hasValue) return;
    final generation = _generation;
    final current = state.requireValue;
    loadingMore = true;
    pageError = null;
    state = AsyncData([...current]);
    var next = current;
    try {
      final page =
          await ref.read(factCheckPageLoaderProvider)(_offset, pageSize);
      if (generation != _generation) return;
      _offset += page.length;
      hasMore = page.length == pageSize;
      final byId = {for (final item in current) item.id: item};
      for (final item in page) {
        byId[item.id] = item;
      }
      next = byId.values.toList();
    } catch (_) {
      if (generation == _generation) {
        pageError = 'Could not load more articles. Tap to retry.';
      }
    } finally {
      if (generation == _generation) {
        loadingMore = false;
        state = AsyncData([...next]);
      }
    }
  }
}

final factCheckByIdProvider =
    FutureProvider.family<FactCheck?, String>((ref, id) {
  return SupabaseService.instance.fetchFactCheckById(id);
});

final outletSourcesProvider =
    FutureProvider.family<List<OutletSource>, String>((ref, factCheckId) {
  return SupabaseService.instance.fetchOutletSources(factCheckId);
});

final coverageAnalysisProvider =
    FutureProvider.family<CoverageAnalysis?, String>((ref, factCheckId) {
  return SupabaseService.instance.fetchCoverageAnalysis(factCheckId);
});

final factCheckV2Provider =
    FutureProvider.family<FactCheckV2?, String>((ref, factCheckId) {
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
