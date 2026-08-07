import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/prop_data.dart';

PropVerdict _verdict(String decision) => PropVerdict(decision: decision);

/// Built through fromJson so the test exercises the real parse path a
/// card actually receives, rather than a hand-assembled object.
PropData _prop({
  String id = 'p1',
  List<String> reasons = const [],
  String decision = '',
}) {
  return PropData.fromJson({
    'id': id,
    'player': 'Drew Romo',
    'sport': 'MLB',
    'matchup': 'Detroit Tigers @ Seattle Mariners',
    'sportsbook': 'PRIZEPICKS',
    'market': 'Batter Hits',
    'line': 0.5,
    'verificationReasons': reasons,
    if (decision.isNotEmpty) 'verdict': {'decision': decision},
  });
}

void main() {
  group('verdict ordering', () {
    test('a play outranks every other decision', () {
      expect(
        _verdict('PLAY_NOW').actionRank,
        greaterThan(_verdict('SHOP').actionRank),
      );
      expect(
        _verdict('SHOP').actionRank,
        greaterThan(_verdict('LEAN').actionRank),
      );
    });

    test('shopping outranks a lean because the edge is full sized', () {
      // Only the price here is wrong on a SHOP; a LEAN is a genuinely
      // smaller edge, so it must not sort above one.
      expect(
        _verdict('SHOP').actionRank,
        greaterThan(_verdict('LEAN').actionRank),
      );
    });

    test('wait sits above a pass but below anything playable today', () {
      expect(
        _verdict('WAIT').actionRank,
        greaterThan(_verdict('PASS').actionRank),
      );
      expect(
        _verdict('WAIT').actionRank,
        lessThan(_verdict('LEAN').actionRank),
      );
    });

    test('a payload with no verdict ranks last rather than crashing', () {
      // Older cached props carry no verdict at all and must not be able to
      // sort above a real play.
      expect(const PropVerdict().actionRank, 0);
      expect(_verdict('SOMETHING_NEW').actionRank, 0);
    });

    test('sorting by rank puts the plays at the top of a mixed board', () {
      final board = [
        _prop(id: 'a', decision: 'PASS'),
        _prop(id: 'b', decision: 'LEAN'),
        _prop(id: 'c', decision: 'PLAY_NOW'),
        _prop(id: 'd', decision: 'WAIT'),
        _prop(id: 'e', decision: 'SHOP'),
      ]..sort(
        (left, right) => right.verdict.actionRank - left.verdict.actionRank,
      );

      expect(
        board.map((prop) => prop.id).toList(),
        ['c', 'e', 'b', 'd', 'a'],
      );
    });
  });

  group('data caveats on the card', () {
    test('an unverifiable source is named rather than passed over', () {
      expect(
        _prop(reasons: ['source_unverified']).dataCaveats,
        ['SOURCE UNVERIFIED'],
      );
    });

    test('an unidentified event is named too', () {
      expect(
        _prop(reasons: ['event_unnamed']).dataCaveats,
        ['EVENT UNCONFIRMED'],
      );
    });

    test('every caveat is reported, not just the first', () {
      expect(
        _prop(reasons: ['source_unverified', 'event_unnamed']).dataCaveats,
        ['SOURCE UNVERIFIED', 'EVENT UNCONFIRMED'],
      );
    });

    test('a missing projection is left to its own dedicated chip', () {
      // The card already says NO MODEL PROJECTION. Repeating it here would
      // read as two separate faults on one prop.
      expect(_prop(reasons: ['projection_missing']).dataCaveats, isEmpty);
      expect(_prop(reasons: ['projection_missing']).hasModelProjection, false);
    });

    test('a fully verified prop carries no caveats', () {
      expect(_prop().dataCaveats, isEmpty);
    });

    test('an unrecognised reason is dropped rather than shown raw', () {
      // A reason the backend adds later must not appear on the card as an
      // untranslated identifier.
      expect(_prop(reasons: ['brand_new_reason']).dataCaveats, isEmpty);
    });
  });
}
