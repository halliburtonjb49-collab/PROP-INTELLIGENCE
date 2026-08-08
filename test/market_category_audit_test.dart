import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/main.dart';

import 'feed_markets.g.dart';

/// Every market key the feed can produce, run through the real categoriser.
///
/// The fantasy defect reached a phone before it reached a test: the market
/// was labelled POINTS and drawn with a fantasy number, and nothing in the
/// suite could see it because the logic lived in two private copies inside
/// widget state. This audit exists so the next mapping error is caught here.
///
/// Every test in that categoriser is a substring match, so the whole
/// correctness argument is ordering: a compound or derived market must be
/// decided before any single-word market whose name it contains.
void main() {
  /// The single word a category must not be reduced to, per market key.
  const mustNotBe = <String, String>{
    'player_fantasy_points': 'POINTS',
    'player_points_rebounds': 'POINTS',
    'player_points_assists': 'POINTS',
    'player_points_rebounds_assists': 'POINTS',
    'player_rebounds_assists': 'REBOUNDS',
    'player_blocks_steals': 'BLOCKS',
    'player_tackles_assists': 'TACKLES',
    'player_double_double': 'POINTS',
  };

  test('no compound market collapses into a single-word category', () {
    final collapsed = <String>[];
    for (final (sport, market) in allFeedMarkets) {
      final wrong = mustNotBe[market];
      if (wrong == null) continue;
      final category = marketCategoryFor(sport, market);
      if (category == wrong) collapsed.add('$sport/$market -> $category');
    }

    expect(collapsed, isEmpty, reason: 'compound markets lost their meaning');
  });

  test('a fantasy market is never called points', () {
    // The exact defect from the board: PLAYER FANTASY POINTS contains
    // POINTS, so a substring test reaches the wrong answer unless FANTASY
    // is decided first.
    for (final sport in ['NBA', 'WNBA']) {
      expect(
        marketCategoryFor(sport, 'player_fantasy_points'),
        'FANTASY SCORE',
        reason: '$sport fantasy market must not read as points',
      );
    }
  });

  test('the plain markets still resolve to themselves', () {
    expect(marketCategoryFor('NBA', 'player_points'), 'POINTS');
    expect(marketCategoryFor('WNBA', 'player_rebounds'), 'REBOUNDS');
    expect(marketCategoryFor('WNBA', 'player_assists'), 'ASSISTS');
  });

  test('the basketball compounds keep their full meaning', () {
    expect(marketCategoryFor('NBA', 'player_points_rebounds_assists'), 'PRA');
    expect(
      marketCategoryFor('NBA', 'player_points_rebounds'),
      'POINTS + REBOUNDS',
    );
    expect(
      marketCategoryFor('NBA', 'player_points_assists'),
      'POINTS + ASSISTS',
    );
    expect(
      marketCategoryFor('NBA', 'player_rebounds_assists'),
      'REBOUNDS + ASSISTS',
    );
    expect(marketCategoryFor('NBA', 'player_blocks_steals'), 'BLOCKS + STEALS');
    expect(marketCategoryFor('NBA', 'player_double_double'), 'DOUBLE DOUBLE');
  });

  test('every feed market resolves to something', () {
    // A market that falls through every test lands on the card as whatever
    // the raw key happened to be, which is how an underscored identifier
    // ends up printed at a reader.
    final unresolved = <String>[];
    for (final (sport, market) in allFeedMarkets) {
      final category = marketCategoryFor(sport, market);
      if (category.trim().isEmpty || category.contains('_')) {
        unresolved.add('$sport/$market -> "$category"');
      }
    }

    expect(unresolved, isEmpty);
  });

  test('two different markets never share one category', () {
    // The general form of every mapping defect found so far. Each test in
    // the categoriser is a substring match, so a broad rule silently
    // swallows the narrower markets whose names contain it: fantasy points
    // became POINTS, four NFL reception markets became RECEPTIONS, and
    // hits+runs+rbis became RBIS. In every case two distinct bets, with
    // very different numbers, were drawn on the card under one name.
    //
    // Collision is the symptom they share, so this is the test that catches
    // the next one without anyone having to guess what it will be.
    final byCategory = <String, List<String>>{};
    for (final (sport, market) in allFeedMarkets) {
      final key = '$sport/${marketCategoryFor(sport, market)}';
      byCategory.putIfAbsent(key, () => []).add(market);
    }
    final collisions = byCategory.entries
        .where((entry) => entry.value.length > 1)
        .map((entry) => '${entry.key} <- ${entry.value.join(", ")}')
        .toList();

    expect(collisions, isEmpty, reason: 'distinct markets share a label');
  });
}
