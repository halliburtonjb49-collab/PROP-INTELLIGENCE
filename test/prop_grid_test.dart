import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/prop_data.dart';
import 'package:prop_intelligence/services/api_service.dart';
import 'package:prop_intelligence/widgets/prop_grid.dart';

class _FailingPropsApi extends ApiService {
  int fetchCalls = 0;

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
  }) {
    fetchCalls += 1;
    return Future<List<PropData>>.error(StateError('test feed unavailable'));
  }
}

void main() {
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
    await tester.pump();

    expect(api.fetchCalls, 1);
    expect(find.text('Unable to load props'), findsOneWidget);
    expect(find.text('RETRY'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    refresh.dispose();
  });
}
