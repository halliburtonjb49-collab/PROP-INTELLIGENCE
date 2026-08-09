import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/prop_data.dart';
import 'package:prop_intelligence/pages/injury_impact_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

PropData impactProp({
  required String id,
  required String player,
  required String sport,
  required String site,
  String event = 'event-1',
  String market = 'points',
  String injury = 'no injury reported',
  String lineup = 'confirmed',
  String roleChange = 'UNKNOWN',
  double? usage,
  double? wowy,
}) => PropData.fromJson({
  'id': id,
  'eventId': event,
  'canonicalPlayerId': 'player-${player.toLowerCase()}',
  'player': player,
  'sport': sport,
  'matchup': 'AWAY @ HOME',
  'sportsbook': site,
  'market': market,
  'marketKey': market,
  'displayMarket': market.toUpperCase(),
  'line': 20.5,
  'currentLine': 20.5,
  'projection': 22.1,
  'selectable': true,
  'piTrustScore': 82,
  'injuryStatus': injury,
  'lineupStatus': lineup,
  'roleChange': roleChange,
  'usageMultiplier': usage,
  'wowyMultiplier': wowy,
  'lastUpdatedUtc': '2026-08-09T15:00:00Z',
});

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('deduplicates the same affected market across prop sites', () {
    final items = buildInjuryImpactItems([
      impactProp(
        id: 'a',
        player: 'Alex Guard',
        sport: 'NBA',
        site: 'PRIZEPICKS',
        injury: 'questionable',
      ),
      impactProp(
        id: 'b',
        player: 'Alex Guard',
        sport: 'NBA',
        site: 'UNDERDOG',
        injury: 'questionable',
      ),
    ]);

    expect(items, hasLength(1));
    expect(items.single.sites, containsAll(['PRIZEPICKS', 'UNDERDOG']));
    expect(items.single.summary.details.join(' '), contains('questionable'));
  });

  test('ranks availability blocks above verified role shifts', () {
    final items = buildInjuryImpactItems([
      impactProp(
        id: 'role',
        player: 'Role Player',
        sport: 'WNBA',
        site: 'PRIZEPICKS',
        roleChange: 'EXPANDED',
        usage: 1.08,
        wowy: 1.12,
      ),
      impactProp(
        id: 'out',
        player: 'Out Player',
        sport: 'MLB',
        site: 'UNDERDOG',
        injury: 'out',
      ),
    ]);

    expect(items.first.level, 'CRITICAL');
    expect(items.last.summary.details.join(' '), contains('With/without'));
  });

  test('does not create an alert from unreported lineup defaults', () {
    final items = buildInjuryImpactItems([
      impactProp(
        id: 'quiet',
        player: 'Quiet Player',
        sport: 'MLB',
        site: 'PRIZEPICKS',
        lineup: 'unknown',
      ),
    ]);

    expect(items, isEmpty);
  });
  testWidgets('phone view summarizes and filters verified impacts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final props = [
      impactProp(
        id: 'out',
        player: 'Out Player',
        sport: 'MLB',
        site: 'UNDERDOG',
        injury: 'out',
      ),
      impactProp(
        id: 'watch',
        player: 'Role Player',
        sport: 'WNBA',
        site: 'PRIZEPICKS',
        roleChange: 'EXPANDED',
        usage: 1.08,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InjuryImpactPage(
            props: props,
            alerts: const [
              {
                'eventId': 'event-alert-1',
                'level': 'CRITICAL',
                'title': 'AVAILABILITY BLOCK',
                'message': 'Out Player is now out.',
              },
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('injury-alert-controls')), findsOne);
    expect(find.byKey(const ValueKey('recent-injury-alerts')), findsOne);
    expect(find.textContaining('Out Player is now out'), findsOne);
    expect(find.byKey(const ValueKey('injury-impact-summary')), findsOne);
    expect(find.text('Out Player'), findsOne);
    await tester.scrollUntilVisible(
      find.text('Role Player'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.text('Role Player'), findsOne);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('injury-filter-CRITICAL')),
      -250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('injury-filter-CRITICAL')));
    await tester.pump();

    expect(find.text('Out Player'), findsOne);
    expect(find.text('Role Player'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
