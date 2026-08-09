import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/prop_data.dart';
import 'package:prop_intelligence/widgets/prop_trust_widgets.dart';

PropData _prop() => PropData(
  id: 'prop-1',
  eventId: 'event-1',
  apiSportsGameId: 'game-1',
  playerId: 'player-1',
  player: 'Test Player',
  sport: 'NBA',
  matchup: 'A vs B',
  sportsbook: 'PRIZEPICKS',
  market: 'Points',
  line: 24.5,
  pick: 'OVER',
  edge: 2,
  imagePath: '',
  piTrustScore: 88,
  piTrustBand: 'EXCELLENT',
  piTrustResearchReady: true,
  piTrustFactors: const [
    {
      'label': 'Feed completeness',
      'score': 24,
      'maxScore': 25,
      'detail': '96% complete.',
    },
  ],
  researchCapsule: const {
    'summary': 'The projection clears the current line.',
    'items': [
      {
        'label': 'Projection vs line',
        'value': '26.1 vs 24.5',
        'detail': 'The model is 1.6 above the line.',
        'tone': 'POSITIVE',
      },
    ],
  },
);

void main() {
  testWidgets('trust badge fits phone width and opens details', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PiTrustBadge(prop: _prop())),
      ),
    );

    expect(find.text('PI TRUST 88'), findsOne);
    await tester.tap(find.byKey(const ValueKey('pi-trust-score-prop-1')));
    await tester.pumpAndSettle();
    expect(find.text('PI TRUST SCORE 88/100'), findsOne);
    expect(find.text('Feed completeness'), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('why capsule renders compact plain-language evidence', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WhyThisPropCapsule(prop: _prop())),
      ),
    );
    expect(find.text('WHY THIS PROP?'), findsOne);
    expect(find.textContaining('Projection vs line'), findsOne);
    expect(find.textContaining('The model is 1.6 above'), findsOne);
    expect(tester.takeException(), isNull);
  });
}
