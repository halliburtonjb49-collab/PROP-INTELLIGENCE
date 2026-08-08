import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/prop_data.dart';
import 'package:prop_intelligence/services/prop_market_identity.dart';

PropData _prop(String marketKey) => PropData.fromJson({
  'id': 'c1',
  'player': 'Angel Reese',
  'sport': 'WNBA',
  'matchup': 'Atlanta Dream @ Washington Mystics',
  'sportsbook': 'PRIZEPICKS',
  'market': 'Fantasy Score',
  'marketKey': marketKey,
  'line': 36.5,
});

void main() {
  test('the canonical key decides fantasy before points', () {
    // This function runs before the rest of the categoriser and returns
    // early, so a defect here is invisible to any test of the fallback --
    // which is exactly how the first fix for this shipped without working.
    expect(canonicalCategoryFromMarketKey(_prop('player_fantasy_points')),
        'FANTASY SCORE');
  });

  test('the compounds still beat their own components', () {
    expect(canonicalCategoryFromMarketKey(_prop('player_points_rebounds_assists')), 'PRA');
    expect(canonicalCategoryFromMarketKey(_prop('player_points_rebounds')), 'POINTS + REBOUNDS');
    expect(canonicalCategoryFromMarketKey(_prop('player_points_assists')), 'POINTS + ASSISTS');
    expect(canonicalCategoryFromMarketKey(_prop('player_rebounds_assists')), 'REBOUNDS + ASSISTS');
  });

  test('the plain markets are unaffected', () {
    expect(canonicalCategoryFromMarketKey(_prop('player_points')), 'POINTS');
    expect(canonicalCategoryFromMarketKey(_prop('player_rebounds')), 'REBOUNDS');
    expect(canonicalCategoryFromMarketKey(_prop('player_assists')), 'ASSISTS');
  });

  test('an unknown key defers rather than guessing', () {
    // Returning empty hands the decision to the fallback categoriser, which
    // knows about sports this function does not.
    expect(canonicalCategoryFromMarketKey(_prop('player_pass_yds')), '');
  });

  test('no two basketball markets share a canonical category', () {
    const markets = [
      'player_points', 'player_rebounds', 'player_assists',
      'player_blocks', 'player_steals', 'player_fantasy_points',
      'player_points_rebounds', 'player_points_assists',
      'player_rebounds_assists', 'player_points_rebounds_assists',
      'player_double_double', 'player_threes',
    ];
    final seen = <String, String>{};
    final collisions = <String>[];
    for (final market in markets) {
      final category = canonicalCategoryFromMarketKey(_prop(market));
      if (category.isEmpty) continue;
      final previous = seen[category];
      if (previous != null) collisions.add('$category <- $previous, $market');
      seen[category] = market;
    }

    expect(collisions, isEmpty);
  });
}
