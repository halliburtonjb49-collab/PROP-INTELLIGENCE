import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/prop_data.dart';
import 'package:prop_intelligence/services/prop_book_group.dart';

PropData _prop({
  required String id,
  required String book,
  String group = 'grp-1',
  double line = 25.5,
  double? overOdds = -110,
  String side = 'OVER',
  bool stale = false,
}) => PropData.fromJson({
  'id': id,
  'player': 'Player',
  'sport': 'WNBA',
  'matchup': 'A @ B',
  'sportsbook': book,
  'market': 'Points',
  'line': line,
  'projection': 27.0,
  'overOdds': overOdds,
  'recommendedSide': side,
  'propGroupId': group,
  'dataStale': stale,
  'selectable': !stale,
});

void main() {
  test('one card per offer, every book still reachable', () {
    // 13,053 distinct props reach the board as 28,194 cards. Collapsing must
    // not cost a single alternative.
    final groups = collapsePropsByBook([
      _prop(id: 'a', book: 'PrizePicks'),
      _prop(id: 'b', book: 'DraftKings'),
      _prop(id: 'c', book: 'FanDuel'),
    ]);

    expect(groups, hasLength(1));
    expect(groups.single.bookCount, 3);
    expect(groups.single.variants.map((prop) => prop.id).toSet(), {
      'a',
      'b',
      'c',
    });
  });

  test('the best price leads the card', () {
    final groups = collapsePropsByBook([
      _prop(id: 'worse', book: 'A', overOdds: -140),
      _prop(id: 'better', book: 'B', overOdds: 120),
      _prop(id: 'middle', book: 'C', overOdds: -110),
    ]);

    expect(groups.single.representative.id, 'better');
  });

  test('a stale book never leads, however good its price', () {
    // Stale lines must not look playable, and a price that cannot be taken
    // is not a better price.
    final groups = collapsePropsByBook([
      _prop(id: 'stale', book: 'A', overOdds: 300, stale: true),
      _prop(id: 'live', book: 'B', overOdds: -115),
    ]);

    expect(groups.single.representative.id, 'live');
    expect(groups.single.bookCount, 2, reason: 'the stale book stays visible');
  });

  test('every variant keeps its own prop id', () {
    // The single highest-risk part of dedup: a pick must land on the book
    // the user chose, not on the one the card happened to open with.
    final groups = collapsePropsByBook([
      _prop(id: 'pp-123', book: 'PrizePicks'),
      _prop(id: 'dk-456', book: 'DraftKings'),
    ]);

    for (final variant in groups.single.variants) {
      expect(variant.id, isNotEmpty);
      expect(variant.id, isNot(groups.single.groupId));
    }
  });

  test('differing lines are surfaced rather than hidden', () {
    final groups = collapsePropsByBook([
      _prop(id: 'a', book: 'A', line: 25.5),
      _prop(id: 'b', book: 'B', line: 26.5),
    ]);

    expect(groups.single.linesDiffer, isTrue);
  });

  test('an unidentified prop is never folded onto another card', () {
    final groups = collapsePropsByBook([
      _prop(id: 'a', book: 'A', group: ''),
      _prop(id: 'b', book: 'B', group: ''),
    ]);

    expect(groups, hasLength(2));
  });

  test('different offers stay separate', () {
    final groups = collapsePropsByBook([
      _prop(id: 'a', book: 'A', group: 'points'),
      _prop(id: 'b', book: 'B', group: 'rebounds'),
    ]);

    expect(groups, hasLength(2));
  });

  test('board order is preserved', () {
    // The caller already sorted by PI score; collapsing must not reorder.
    final groups = collapsePropsByBook([
      _prop(id: 'first', book: 'A', group: 'one'),
      _prop(id: 'second', book: 'B', group: 'two'),
      _prop(id: 'first-alt', book: 'C', group: 'one'),
    ]);

    expect(groups.map((group) => group.groupId).toList(), ['one', 'two']);
  });

  test('ties break stably so books do not swap between rebuilds', () {
    List<String> leadFor(List<PropData> props) =>
        collapsePropsByBook(props).map((g) => g.representative.id).toList();

    final forward = leadFor([
      _prop(id: 'a', book: 'Alpha'),
      _prop(id: 'b', book: 'Beta'),
    ]);
    final reversed = leadFor([
      _prop(id: 'b', book: 'Beta'),
      _prop(id: 'a', book: 'Alpha'),
    ]);

    expect(forward, reversed);
  });
}
