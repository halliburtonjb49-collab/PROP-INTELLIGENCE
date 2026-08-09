import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/prop_data.dart';
import 'package:prop_intelligence/widgets/injury_impact_alert.dart';
import 'package:prop_intelligence/widgets/personal_edge_profile.dart';
import 'package:prop_intelligence/widgets/prop_research_assistant.dart';

PropData prop({
  required String id,
  required String player,
  int trust = 80,
  int confidence = 65,
  String injury = 'no injury reported',
  String lineup = 'confirmed',
}) => PropData.fromJson({
  'id': id,
  'eventId': 'event-$id',
  'apiSportsGameId': 'game-$id',
  'player': player,
  'sport': 'MLB',
  'sportsbook': 'PRIZEPICKS',
  'market': 'hits',
  'displayMarket': 'Hits',
  'line': 1.5,
  'currentLine': 1.5,
  'openingLine': 1.0,
  'projection': 1.8,
  'selectable': true,
  'piTrustScore': trust,
  'piTrustBand': 'STRONG',
  'confidence': confidence,
  'injuryStatus': injury,
  'lineupStatus': lineup,
  'verdict': {
    'decision': 'LEAN',
    'headline': 'Small over lean',
    'reason': 'Projection is above the line.',
  },
});

void main() {
  test('personal edge requires real samples and selects strongest segment', () {
    final profile = buildPersonalEdgeProfile({
      'leg_performance_by_sport': [
        {'name': 'MLB', 'resolved_legs': 12, 'leg_hit_rate': 58.3},
        {'name': 'NBA', 'resolved_legs': 2, 'leg_hit_rate': 100.0},
      ],
      'leg_performance_by_market': [
        {'name': 'Hits', 'resolved_legs': 8, 'leg_hit_rate': 62.5},
      ],
      'leg_performance_by_side': [
        {'name': 'UNDER', 'resolved_legs': 7, 'leg_hit_rate': 57.1},
      ],
      'leg_performance_by_confidence': [
        {'name': '60-69%', 'resolved_legs': 9, 'leg_hit_rate': 66.7},
      ],
    });
    expect(
      profile.map((item) => item.name),
      containsAll(['MLB', 'Hits', 'UNDER', '60-69%']),
    );
    expect(profile.map((item) => item.name), isNot(contains('NBA')));
  });

  test(
    'injury impact reports verified availability without inventing delta',
    () {
      final summary = buildInjuryImpactSummary(
        prop(id: 'a', player: 'A', injury: 'questionable', lineup: 'projected'),
      );
      expect(summary.isPresent, isTrue);
      expect(summary.details.join(' '), contains('questionable'));
      expect(summary.details.join(' '), contains('projected'));
    },
  );

  test(
    'research assistant compares two real props and distinguishes trust',
    () {
      final answer = answerPropResearchQuestion(
        prop(id: 'a', player: 'Alice', trust: 88, confidence: 61),
        'Compare these two props',
        comparison: prop(id: 'b', player: 'Bob', trust: 70, confidence: 72),
      );
      expect(answer, contains('Alice'));
      expect(answer, contains('Bob'));
      expect(answer, contains('stronger data foundation'));
    },
  );

  testWidgets('Research AI opens and answers a grounded why question', (
    tester,
  ) async {
    final current = prop(id: 'a', player: 'Alice');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PropResearchAiButton(prop: current)),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('ask-pi-research')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Why is this a lean?'));
    await tester.pump();
    expect(
      find.textContaining('Projection 1.8 versus line 1.5'),
      findsOneWidget,
    );
  });
}
