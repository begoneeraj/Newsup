import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newsup/src/models/fact_check.dart';
import 'package:newsup/src/providers/fact_check_providers.dart';

FactCheck sampleFact(int id) => FactCheck(
    id: '$id',
    claimText: 'Claim $id',
    origin: 'Publisher',
    status: FactCheckStatus.unverified,
    evidenceConfidence: 0,
    sourceReliability: SourceReliability.low,
    independentConfirmations: 0,
    officialConfirmation: false,
    sources: const [],
    createdAt: DateTime.utc(2026));

void main() {
  test(
      'Feed loads beyond the server single-response cap with independent pages',
      () async {
    final offsets = <int>[];
    final container = ProviderContainer(overrides: [
      factCheckPageLoaderProvider.overrideWithValue((offset, limit) async {
        offsets.add(offset);
        return List.generate(
            offset < 1100 ? limit : 1, (i) => sampleFact(offset + i));
      })
    ]);
    addTearDown(container.dispose);
    await container.read(factChecksProvider.future);
    for (var i = 0; i < 11; i++) {
      await container.read(factChecksProvider.notifier).loadMore();
    }
    expect(container.read(factChecksProvider).requireValue.length, 1101);
    expect(offsets.last, 1100);
    expect(container.read(factChecksProvider.notifier).hasMore, isFalse);
  });

  test('Failed next page preserves articles and retries the same offset',
      () async {
    var fail = true;
    final offsets = <int>[];
    final container = ProviderContainer(overrides: [
      factCheckPageLoaderProvider.overrideWithValue((offset, limit) async {
        offsets.add(offset);
        if (offset > 0 && fail) throw StateError('offline');
        return List.generate(limit, (i) => sampleFact(offset + i));
      })
    ]);
    addTearDown(container.dispose);
    await container.read(factChecksProvider.future);
    await container.read(factChecksProvider.notifier).loadMore();
    expect(container.read(factChecksProvider).requireValue.length, 100);
    expect(container.read(factChecksProvider.notifier).pageError, isNotNull);
    fail = false;
    await container.read(factChecksProvider.notifier).loadMore();
    expect(offsets, [0, 100, 100]);
    expect(container.read(factChecksProvider).requireValue.length, 200);
  });

  test('Refresh discards an older in-flight next-page response', () async {
    final pending = Completer<List<FactCheck>>();
    var refreshed = false;
    final container = ProviderContainer(overrides: [
      factCheckPageLoaderProvider.overrideWithValue((offset, limit) async {
        if (offset > 0) return pending.future;
        return List.generate(
            limit, (i) => sampleFact(i + (refreshed ? 2000 : 0)));
      })
    ]);
    addTearDown(container.dispose);
    final keepAlive = container.listen(factChecksProvider, (_, __) {});
    addTearDown(keepAlive.close);
    await container.read(factChecksProvider.future);
    final request = container.read(factChecksProvider.notifier).loadMore();
    refreshed = true;
    container.invalidate(factChecksProvider);
    await container.read(factChecksProvider.future);
    pending.complete([sampleFact(100)]);
    await request;
    expect(container.read(factChecksProvider).requireValue.first.id, '2000');
    expect(container.read(factChecksProvider).requireValue.length, 100);
  });
}
