import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/widgets/elite_prop_card.dart';

void main() {
  testWidgets('does not invent historical performance when data is missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ElitePropCard(
              playerName: 'Test Player',
              propType: 'Points',
              sportsbookLine: 24.5,
              americanOdds: -110,
              aiProjection: 26.2,
              edgePercentage: 4.8,
              isUserPremium: true,
              propData: {
                'source_provider': 'Verified Feed',
                'recommended_side': 'OVER',
                'odds_data': [
                  {'bookmaker': 'Book A', 'line': 24.5, 'over_odds': -115},
                  {'bookmaker': 'Book B', 'line': 24.5, 'over_odds': 105},
                  {'bookmaker': 'Book C', 'line': 24.5, 'over_odds': -105},
                ],
              },
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('0 verified recent games'), findsOneWidget);
    await tester.tap(find.text('Test Player'));
    await tester.pumpAndSettle();
    expect(find.text('DATA PENDING'), findsOneWidget);
    expect(find.text('WHY THIS PICK?'), findsOneWidget);
    expect(find.text('LINE SHOP'), findsOneWidget);
    expect(find.text('BEST • Book B'), findsOneWidget);
    expect(find.text('24.5  +105'), findsOneWidget);
    expect(find.textContaining('3 books compared'), findsOneWidget);
    expect(find.textContaining('Projection is 1.7 above'), findsOneWidget);
    expect(find.textContaining('Estimated edge is +4.8%'), findsOneWidget);
    expect(
      find.textContaining('Verified recent-game history is not available'),
      findsOneWidget,
    );
    expect(find.text('80% Hit'), findsNothing);
  });
}
