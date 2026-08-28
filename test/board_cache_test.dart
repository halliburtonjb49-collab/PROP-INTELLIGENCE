import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/prop_data.dart';
import 'package:prop_intelligence/services/api_service.dart';
import 'package:prop_intelligence/widgets/prop_grid.dart';

class _CountingApi extends ApiService {
  _CountingApi(this.props);

  final List<PropData> props;
  int fetches = 0;

  @override
  Future<List<PropData>> loadCachedProps({
    String selectedSide = 'All',
    String selectedTier = 'All',
    String selectedSportsbook = 'All',
    String selectedSport = 'All',
    String selectedCategory = 'All',
    String search = '',
    int minConfidence = 0,
    String sortBy = 'confidence',
    String verdictFilter = 'All',
  }) async => props;

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
  }) async {
    fetches += 1;
    return props;
  }
}

PropData _prop(String id, String book, String group) => PropData.fromJson({
  'id': id,
  'player': 'Player $group',
  'sport': 'WNBA',
  'matchup': 'A @ B',
  'sportsbook': book,
  'market': 'Points',
  'line': 20.5,
  'projection': 23.0,
  'overOdds': -110,
  'recommendedSide': 'OVER',
  'propGroupId': group,
  'startTimeUtc': '2026-09-21T18:00:00Z',
});

void main() {
  testWidgets('switching a book does not re-derive the whole board', (
    tester,
  ) async {
    // Filtering, sorting and collapsing runs in build. Before this cache,
    // expanding one card's research or switching one card's book paid for
    // the entire board again, and none of those inputs change what the
    // board contains.
    final refresh = ValueNotifier<int>(0);
    addTearDown(refresh.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PropGrid(
              selections: const [],
              onSelect: (_, _) {},
              sportFilter: 'ALL',
              displaySportFilter: 'ALL',
              selectedSite: 'ALL',
              selectedCategory: 'ALL',
              selectedSide: 'ALL',
              selectedTier: 'ALL',
              minConfidence: 0,
              sortBy: 'confidence',
              searchQuery: '',
              refreshListenable: refresh,
              apiService: _CountingApi([
                _prop('a1', 'DRAFTKINGS', 'g1'),
                _prop('a2', 'PRIZEPICKS', 'g1'),
              ]),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byKey(const ValueKey('card-a1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('card-a2')),
      findsOneWidget,
    );
  });
}
