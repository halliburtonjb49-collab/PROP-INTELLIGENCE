import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/prop_data.dart';
import 'package:prop_intelligence/services/api_service.dart';
import 'package:prop_intelligence/widgets/prop_grid.dart';

class _TwoBookApi extends ApiService {
  _TwoBookApi(this.props);

  final List<PropData> props;

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
  }) async => props;
}

PropData _prop({
  required String id,
  required String book,
  required double line,
  double overOdds = -110,
}) => PropData.fromJson({
  'id': id,
  'player': 'Grouped Player',
  'sport': 'WNBA',
  'matchup': 'A @ B',
  'sportsbook': book,
  'market': 'Points',
  'line': line,
  'projection': line + 2,
  'overOdds': overOdds,
  'recommendedSide': 'OVER',
  'propGroupId': 'grp-1',
  'propGroupBookCount': 2,
});

Future<List<PropData>> _pumpGrid(WidgetTester tester) async {
  final picked = <PropData>[];
  final refresh = ValueNotifier<int>(0);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PropGrid(
            selections: const [],
            onSelect: (prop, _) => picked.add(prop),
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
            apiService: _TwoBookApi([
              _prop(id: 'dk-1', book: 'DraftKings', line: 25.5, overOdds: -140),
              _prop(id: 'pp-2', book: 'PrizePicks', line: 26.5, overOdds: 120),
            ]),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  addTearDown(refresh.dispose);
  return picked;
}

void main() {
  testWidgets('two books become one card that still offers both', (
    tester,
  ) async {
    await _pumpGrid(tester);

    expect(find.byKey(const ValueKey('book-switcher-grp-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('book-option-dk-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('book-option-pp-2')), findsOneWidget);
  });

  testWidgets('the better price leads and both lines are shown', (
    tester,
  ) async {
    await _pumpGrid(tester);

    // +120 beats -140, so PrizePicks opens the card, and the books disagree
    // about the number, which is the reason to shop.
    expect(find.textContaining('PRIZEPICKS 26.5'), findsOneWidget);
    expect(find.textContaining('DRAFTKINGS 25.5'), findsOneWidget);
    expect(find.text('LINES VARY'), findsOneWidget);
  });

  testWidgets('a pick lands on the book the user switched to', (tester) async {
    // The single highest-risk part of collapsing duplicates: the card opens
    // on one book, so a pick after switching must not silently use it.
    final picked = await _pumpGrid(tester);

    await tester.tap(find.byKey(const ValueKey('book-option-dk-1')));
    await tester.pump();
    await tester.tap(find.text('OVER').first);
    await tester.pump();

    expect(picked, isNotEmpty);
    expect(picked.last.id, 'dk-1');
    expect(picked.last.sportsbook, 'DraftKings');
  });
}
