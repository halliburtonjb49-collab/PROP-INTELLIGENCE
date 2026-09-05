import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/prop_data.dart';
import 'package:prop_intelligence/pages/prop_alerts_page.dart';
import 'package:prop_intelligence/pages/search_players_page.dart';

PropData _prop(
  String id,
  String player, {
  String matchup = 'TEAM A @ TEAM B',
  String market = 'POINTS',
}) {
  return PropData.fromJson({
    'id': id,
    'player': player,
    'sport': 'NBA',
    'matchup': matchup,
    'sportsbook': 'PRIZEPICKS',
    'market': market,
    'line': 20.5,
    'confidence': 70,
  });
}

void main() {
  testWidgets('player directory deduplicates, filters and clears', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchPlayersPage(
            props: [
              _prop('one', 'Alyssa Thomas', market: 'REBOUNDS'),
              _prop('duplicate', 'Alyssa Thomas', market: 'ASSISTS'),
              _prop('two', 'Breanna Stewart', matchup: 'NYL @ CON'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('2 of 2 players'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('player-search-input-0')),
      'rebounds',
    );
    await tester.pump();
    expect(find.text('1 of 2 players'), findsOneWidget);
    expect(find.text('Alyssa Thomas'), findsOneWidget);
    expect(find.text('Breanna Stewart'), findsNothing);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(find.text('2 of 2 players'), findsOneWidget);
  });

  testWidgets('alerts page shows count and research details', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PropAlertsPage(
          alerts: [
            PropAlertData(
              sport: 'WNBA',
              title: 'Line moved',
              message: 'The provider line moved by 1.5 points.',
              edge: 8,
              book: 'PRIZEPICKS',
              time: '2m ago',
            ),
          ],
        ),
      ),
    );

    expect(find.text('1 alerts'), findsOneWidget);
    expect(find.text('Line moved'), findsOneWidget);
    expect(find.text('Edge: 8%'), findsOneWidget);
    expect(find.text('Book: PRIZEPICKS'), findsOneWidget);
  });

  testWidgets('an empty alert feed is not counted as a real alert', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: PropAlertsPage(alerts: [])),
    );

    expect(find.text('0 alerts'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('prop-alerts-empty-state')),
      findsOneWidget,
    );
    expect(find.text('No Props Loaded'), findsNothing);
  });

  testWidgets('prop alerts can be closed from the header', (tester) async {
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: PropAlertsPage(alerts: const [], onClose: () => closed = true),
      ),
    );

    await tester.tap(find.byTooltip('Close prop alerts'));
    expect(closed, isTrue);
  });
}
