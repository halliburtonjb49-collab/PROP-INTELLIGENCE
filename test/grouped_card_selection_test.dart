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
    bool trackBoardLoad = false,
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
  testWidgets('two books remain available through one grouped card', (
    tester,
  ) async {
    await _pumpGrid(tester);

    expect(find.byKey(const ValueKey('card-pp-2')), findsOneWidget);
    expect(find.text('2 CURRENT LINE OPTIONS'), findsOneWidget);
  });

  testWidgets('the better price leads and both lines are shown', (
    tester,
  ) async {
    await _pumpGrid(tester);

    // +120 beats -140, so PrizePicks opens the card, and the books disagree
    // about the number, which is the reason to shop.
    expect(find.textContaining('26.5'), findsWidgets);
    expect(find.text('PRIZEPICKS'), findsOneWidget);
    await tester.tap(find.text('2 CURRENT LINE OPTIONS'));
    await tester.pumpAndSettle();
    expect(find.textContaining('25.5'), findsWidgets);
    expect(find.text('DRAFTKINGS'), findsWidgets);
  });

  testWidgets('each site-specific card opens its own intelligence', (
    tester,
  ) async {
    await _pumpGrid(tester);
    await tester.ensureVisible(find.text('2 CURRENT LINE OPTIONS'));
    await tester.tap(find.text('2 CURRENT LINE OPTIONS'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Grouped Player'), findsWidgets);
    expect(find.text('DRAFTKINGS'), findsWidgets);
  });
}
