import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/prop_data.dart';
import 'package:prop_intelligence/models/prop_page.dart';
import 'package:prop_intelligence/services/api_service.dart';
import 'package:prop_intelligence/services/prop_repository.dart';
import 'package:prop_intelligence/services/prop_sync_coordinator.dart';
import 'package:prop_intelligence/widgets/prop_grid.dart';

class _FailingPropsApi extends ApiService {
  int fetchCalls = 0;
  bool requestedInitialReliability = false;
  int requestedLimit = 0;

  @override
  Future<List<PropData>> loadCachedProps({
    String? accessScope,
    String selectedSide = 'All',
    String selectedTier = 'All',
    String selectedSportsbook = 'All',
    String selectedSport = 'All',
    String selectedCategory = 'All',
    String search = '',
    int minConfidence = 0,
    String sortBy = 'confidence',
    String verdictFilter = 'All',
  }) async => const [];

  @override
  Future<List<PropData>> fetchProps({
    String selectedSide = 'All',
    String selectedTier = 'All',
    String selectedSportsbook = 'All',
    String selectedSport = 'All',
    String selectedCategory = 'All',
    String search = '',
    int minConfidence = 0,
    String sortBy = 'confidence',
    String verdictFilter = 'All',
    int limit = 75,
    int offset = 0,
    bool includeReliability = true,
    bool trackBoardLoad = false,
  }) {
    fetchCalls += 1;
    requestedInitialReliability = includeReliability;
    requestedLimit = limit;
    return Future<List<PropData>>.error(StateError('test feed unavailable'));
  }
}

void main() {
  test('Top PI Picks displays no more than five qualified props', () {
    expect(topPickVisibleCount(0), 0);
    expect(topPickVisibleCount(2), 2);
    expect(topPickVisibleCount(12), 5);
  });

  test('filtered player search does not report a sport-wide outage', () {
    expect(
      shouldShowSportSeasonEmptyState(
        normalizedSport: 'MLB',
        hasSecondaryFilters: true,
      ),
      isFalse,
    );
    expect(
      shouldShowSportSeasonEmptyState(
        normalizedSport: 'MLB',
        hasSecondaryFilters: false,
      ),
      isTrue,
    );
  });

  testWidgets('PropGrid owns and explains a feed failure independently', (
    tester,
  ) async {
    final api = _FailingPropsApi();
    final refresh = ValueNotifier<int>(0);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PropGrid(
              selections: const [],
              onSelect: (_, _) {},
              sportFilter: 'NBA',
              displaySportFilter: 'NBA',
              selectedSite: 'ALL',
              selectedCategory: 'ALL',
              selectedSide: 'ALL',
              selectedTier: 'ALL',
              minConfidence: 0,
              sortBy: 'confidence',
              searchQuery: 'module-error-contract',
              refreshListenable: refresh,
              apiService: api,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // The board makes one automatic recovery attempt before presenting the
    // durable error state, so a brief provider interruption stays invisible.
    await tester.pump(const Duration(seconds: 3));

    expect(api.fetchCalls, 2);
    expect(api.requestedInitialReliability, isFalse);
    expect(api.requestedLimit, 24);
    expect(find.text('Unable to load props'), findsOneWidget);
    expect(find.text('RETRY'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    refresh.dispose();
  });

  testWidgets('PropGrid renders the enabled shared repository path', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    addTearDown(tester.view.reset);
    final api = _FailingPropsApi();
    final refresh = ValueNotifier<int>(0);
    late final PropSyncCoordinator coordinator;
    final repository = PropRepository(
      loader: (query) async => PropPage(
        query: query,
        rows: [
          PropData.fromJson({
            'id': 'shared-path-prop',
            'event_id': 'event-1',
            'player_id': 'player-1',
            'player_name': 'Shared Path Player',
            'sport': 'NBA',
            'matchup': 'A @ B',
            'sportsbook': 'PRIZEPICKS',
            'market_type': 'Points',
            'line': 20.5,
            'pick': 'OVER',
            'edge': 4,
            'image_path': '',
            'display_time': '7:30 PM',
            'start_time_utc': DateTime.now()
                .add(const Duration(hours: 2))
                .toUtc()
                .toIso8601String(),
            'game_status': 'scheduled',
          }),
        ],
        catalogCount: 1,
        totalCount: 1,
        facetCount: 1,
        categoryCounts: const {'Points': 1},
        totalCategoryCounts: const {'Points': 1},
        playableCategoryCounts: const {'Points': 1},
        sportCounts: const {'NBA': 1},
        sportsbookCounts: const {'PRIZEPICKS': 1},
        verdictCounts: const {},
        sportCategoryCounts: const {
          'NBA': {'Points': 1},
        },
        totalSportCategoryCounts: const {
          'NBA': {'Points': 1},
        },
        playableSportCategoryCounts: const {
          'NBA': {'Points': 1},
        },
        providerCoverage: const {},
        providerReliability: const {},
        feedSource: 'mock',
        feedIsRecovery: false,
        receivedAt: DateTime.utc(2026, 9, 6),
      ),
    );
    coordinator = PropSyncCoordinator(
      repository: repository,
      initialScope: 'test-scope',
      reconcileInterval: const Duration(days: 1),
    );
    PropPage? delivered;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PropGrid(
              selections: const [],
              onSelect: (_, _) {},
              sportFilter: 'NBA',
              displaySportFilter: 'NBA',
              selectedSite: 'ALL',
              selectedCategory: 'ALL',
              selectedSide: 'ALL',
              selectedTier: 'ALL',
              minConfidence: 0,
              sortBy: 'confidence',
              searchQuery: '',
              refreshListenable: refresh,
              apiService: api,
              syncCoordinator: coordinator,
              syncManagerEnabledOverride: true,
              siteFirstLayout: true,
              onPropPageLoaded: (page) => delivered = page,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pi-sync-status')), findsOneWidget);
    expect(delivered?.totalCount, 1);
    expect(delivered?.rows.single.id, 'shared-path-prop');
    final card = find.byKey(
      const ValueKey('site-first-prop-card-shared-path-prop'),
    );
    final under = find.byKey(
      const ValueKey('site-first-under-shared-path-prop'),
    );
    final over = find.byKey(const ValueKey('site-first-over-shared-path-prop'));
    final research = find.byKey(
      const ValueKey('site-first-research-shared-path-prop'),
    );
    expect(under, findsOneWidget);
    expect(over, findsOneWidget);
    expect(research, findsOneWidget);
    expect(find.textContaining('7:30 PM'), findsWidgets);
    expect(
      tester.getRect(under).bottom,
      lessThanOrEqualTo(tester.getRect(card).bottom),
    );
    expect(
      tester.getRect(over).bottom,
      lessThanOrEqualTo(tester.getRect(card).bottom),
    );
    expect(
      tester.getRect(research).bottom,
      lessThanOrEqualTo(tester.getRect(card).bottom),
    );

    await tester.tap(research);
    await tester.pumpAndSettle();
    final close = find.byKey(
      const ValueKey('close-pi-intelligence-shared-path-prop'),
    );
    final signal = find.byKey(
      const ValueKey('research-signal-badge-shared-path-prop'),
    );
    expect(close, findsOneWidget);
    expect(signal, findsOneWidget);
    expect(
      tester.getRect(signal).right,
      lessThanOrEqualTo(tester.getRect(close).left),
      reason: 'the close control must not cover the PI signal badge',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    coordinator.dispose();
    refresh.dispose();
  });
}
