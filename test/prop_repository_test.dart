import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:prop_intelligence/models/prop_data.dart';
import 'package:prop_intelligence/models/prop_page.dart';
import 'package:prop_intelligence/services/prop_repository.dart';
import 'package:prop_intelligence/services/prop_sync_coordinator.dart';

PropData _prop(String id, {double line = 1.5}) => PropData.fromJson({
  'id': id,
  'event_id': 'event-$id',
  'player_id': 'player-$id',
  'player_name': 'Player $id',
  'sport': 'MLB',
  'matchup': 'A @ B',
  'sportsbook': 'PRIZEPICKS',
  'market_type': 'Hits',
  'line': line,
  'pick': 'OVER',
  'edge': 4,
  'image_path': '',
});

PropPage _page(PropQuery query, String id, {int count = 1}) => PropPage(
  query: query,
  rows: [_prop(id)],
  catalogCount: count,
  totalCount: count,
  facetCount: count,
  categoryCounts: {'Hits': count},
  totalCategoryCounts: {'Hits': count},
  playableCategoryCounts: {'Hits': count},
  sportCounts: {'MLB': count},
  sportsbookCounts: {'PRIZEPICKS': count},
  verdictCounts: {'PLAY_NOW': count},
  sportCategoryCounts: {
    'MLB': {'Hits': count},
  },
  totalSportCategoryCounts: {
    'MLB': {'Hits': count},
  },
  playableSportCategoryCounts: {
    'MLB': {'Hits': count},
  },
  providerCoverage: {'PRIZEPICKS': count},
  providerReliability: {
    'PRIZEPICKS': {'status': 'CURRENT'},
  },
  feedSource: 'mock',
  feedIsRecovery: false,
  receivedAt: DateTime.utc(2026, 9, 6),
);

PropQuery _query({
  String sport = 'MLB',
  String scope = 'user-1|premium',
  int offset = 0,
}) => PropQuery(sport: sport, accessScope: scope, offset: offset);

void main() {
  test('query identity includes filters, pagination, and access scope', () {
    final base = _query();
    expect(base.key, isNot(_query(sport: 'WNBA').key));
    expect(base.key, isNot(_query(offset: 24).key));
    expect(base.key, isNot(_query(scope: 'user-2|premium').key));
  });

  test('rows and all response metadata are immutable and stay together', () {
    final page = _page(_query(), 'a');
    expect(() => page.rows.add(_prop('b')), throwsUnsupportedError);
    expect(() => page.categoryCounts['Hits'] = 2, throwsUnsupportedError);
    expect(
      () => page.sportCategoryCounts['MLB']!['Hits'] = 2,
      throwsUnsupportedError,
    );
    expect(
      () => (page.providerReliability['PRIZEPICKS'] as Map)['status'] = 'DOWN',
      throwsUnsupportedError,
    );
    expect(page.rows.single.id, 'a');
    expect(page.totalCount, 1);
  });

  test('identical concurrent requests share one in-flight request', () async {
    final completer = Completer<PropPage>();
    var calls = 0;
    final repository = PropRepository(
      loader: (query) {
        calls++;
        return completer.future;
      },
    )..setScope('user-1|premium');
    final query = _query();

    final first = repository.load(query);
    final second = repository.load(query);
    expect(calls, 1);
    completer.complete(_page(query, 'shared'));

    expect(identical(await first, await second), isTrue);
    repository.dispose();
  });

  test('a newer account scope rejects an older response', () async {
    final completer = Completer<PropPage>();
    final repository = PropRepository(loader: (_) => completer.future)
      ..setScope('user-1|premium');
    final oldQuery = _query();
    final oldRequest = repository.load(oldQuery);

    repository.setScope('user-2|free');
    completer.complete(_page(oldQuery, 'old'));

    await expectLater(oldRequest, throwsA(isA<ObsoletePropRequest>()));
    expect(repository.cacheSize, 0);
    repository.dispose();
  });

  test(
    'refresh keeps the saved page visible and bounds memory cache',
    () async {
      final completions = <String, Completer<PropPage>>{};
      final repository = PropRepository(
        maxEntries: 2,
        loader: (query) =>
            completions.putIfAbsent(query.key, Completer.new).future,
      )..setScope('user-1|premium');
      final query = _query();
      final subscription = repository.subscribe(query);
      final first = repository.load(query);
      completions[query.key]!.complete(_page(query, 'saved'));
      await first;

      completions.remove(query.key);
      final refresh = repository.load(query, force: true);
      expect(subscription.state.value.status, PropPageStatus.updating);
      expect(subscription.state.value.page!.rows.single.id, 'saved');
      completions[query.key]!.complete(_page(query, 'fresh'));
      await refresh;

      for (final sport in ['WNBA', 'NFL']) {
        final q = _query(sport: sport);
        final pending = repository.load(q);
        completions[q.key]!.complete(_page(q, sport));
        await pending;
      }
      expect(repository.cacheSize, 2);
      subscription.dispose();
      repository.dispose();
    },
  );

  test('different filters cannot exchange rows or metadata', () async {
    final repository = PropRepository(
      loader: (query) async =>
          _page(query, query.sport, count: query.sport == 'MLB' ? 5 : 9),
    )..setScope('user-1|premium');

    final mlb = await repository.load(_query());
    final wnba = await repository.load(_query(sport: 'WNBA'));
    expect(mlb.rows.single.id, 'MLB');
    expect(mlb.totalCount, 5);
    expect(wnba.rows.single.id, 'WNBA');
    expect(wnba.totalCount, 9);
    repository.dispose();
  });

  testWidgets('coordinator pauses polling and reconciles once on resume', (
    tester,
  ) async {
    var calls = 0;
    final repository = PropRepository(
      loader: (query) async => _page(query, 'result-${++calls}'),
    );
    final coordinator = PropSyncCoordinator(
      repository: repository,
      initialScope: 'user-1|premium',
      reconcileInterval: const Duration(milliseconds: 10),
    );
    final query = _query();
    final subscription = coordinator.subscribe(query);
    await coordinator.load(query);

    coordinator.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 35));
    expect(calls, 1);

    coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls, 2);

    subscription.dispose();
    coordinator.didChangeAppLifecycleState(AppLifecycleState.paused);
    coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 20));
    expect(calls, 2);
    coordinator.dispose();
  });
}
