import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/prop_data.dart';
import 'package:prop_intelligence/models/slip_selection.dart';
import 'package:prop_intelligence/services/prop_book_group.dart';
import 'package:prop_intelligence/widgets/tablet_market_toolbar.dart';
import 'package:prop_intelligence/widgets/tablet_prop_table.dart';

void main() {
  testWidgets('tablet market toolbar exposes the target controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(820, 1180));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final searchController = TextEditingController();
    addTearDown(searchController.dispose);
    String? selectedSport;
    String? selectedQuickFilter;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TabletMarketToolbar(
              selectedSport: 'MLB',
              onSelectSport: (value) => selectedSport = value,
              selectedSite: 'PRIZEPICKS',
              sitePropCount: 24,
              onChangeSite: () {},
              searchController: searchController,
              onSearchChanged: (_) {},
              onOpenFilters: () {},
              selectedQuickFilter: 'TOP PI PICKS',
              onSelectQuickFilter: (value) => selectedQuickFilter = value,
              playablePropCount: 24,
              bestPiScore: 86,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('tablet-market-toolbar')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('tablet-provider-selector')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('tablet-search-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('tablet-filter-button')), findsOneWidget);
    expect(find.text('PLAYABLE PROPS'), findsOneWidget);
    expect(find.text('BEST PI SCORE'), findsOneWidget);
    expect(find.text('86'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tablet-sport-NFL')));
    await tester.pump();
    expect(selectedSport, 'NFL');

    await tester.tap(
      find.byKey(const ValueKey('tablet-quick-filter-TRENDING')),
    );
    await tester.pump();
    expect(selectedQuickFilter, 'TRENDING');
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet prop table renders real model fields and pick actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(820, 1180));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final prop = PropData.fromJson({
      'id': 'judge-hrrbi',
      'propGroupId': 'judge-hrrbi-group',
      'player': 'Aaron Judge',
      'sport': 'MLB',
      'matchup': 'NYY vs BOS',
      'sportsbook': 'PRIZEPICKS',
      'market': 'Hits + Runs + RBIs',
      'display_market': 'Hits + Runs + RBIs',
      'display_time': '7:05 PM',
      'line': 2.5,
      'currentLine': 2.5,
      'openingLine': 2.0,
      'projection': 3.1,
      'recommendedSide': 'OVER',
      'recommendationAvailable': true,
      'confidence': 86,
      'piTrustScore': 86,
      'edge': 0.6,
      'pick': 'OVER',
      'overOdds': -110,
      'underOdds': -110,
      'imagePath': '',
    });
    PickSide? selectedSide;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: TabletPropTable(
                groups: [
                  PropBookGroup(representative: prop, variants: [prop]),
                ],
                selections: const <SlipSelection>[],
                onSelect: (_, side) => selectedSide = side,
                onShowLineAlternatives: (_) async {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('tablet-prop-table-header')),
      findsOneWidget,
    );
    expect(find.text('Aaron Judge'), findsOneWidget);
    expect(find.text('Hits + Runs + RBIs'), findsOneWidget);
    expect(find.text('86'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('tablet-over-judge-hrrbi')),
      findsOneWidget,
    );
    expect(selectedSide, isNull);
    expect(tester.takeException(), isNull);
  });
}
