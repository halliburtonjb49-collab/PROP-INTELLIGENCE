import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/prop_data.dart';

void main() {
  test('a verdict is read from the payload', () {
    final prop = PropData.fromJson(const {
      'id': 'v1',
      'player': 'Test Player',
      'sport': 'MLB',
      'matchup': 'Detroit Tigers @ Seattle Mariners',
      'sportsbook': 'PRIZEPICKS',
      'market': 'Batter Hits',
      'line': 0.5,
      'verdict': {
        'decision': 'PLAY_NOW',
        'side': 'OVER',
        'headline': 'PLAY OVER NOW',
        'reason': 'The model gives Over 67% against a settled line.',
        'confidence': 67,
        'reasons': <String>[],
        'maximumPlayableLine': 6.7,
        'betterPriceAt': '',
        'recheck': '',
        'actionable': true,
      },
    });

    expect(prop.verdict.isPresent, isTrue);
    expect(prop.verdict.decision, 'PLAY_NOW');
    expect(prop.verdict.headline, 'PLAY OVER NOW');
    expect(prop.verdict.maximumPlayableLine, 6.7);
    expect(prop.verdict.actionable, isTrue);
  });

  test('a payload with no verdict renders nothing rather than an empty block', () {
    // Older responses predate the verdict. An empty bordered box at the top
    // of every card would be worse than no box.
    final prop = PropData.fromJson(const {
      'id': 'legacy',
      'player': 'Test Player',
      'sport': 'MLB',
      'matchup': 'Detroit Tigers @ Seattle Mariners',
      'sportsbook': 'PRIZEPICKS',
      'market': 'Batter Hits',
      'line': 0.5,
    });

    expect(prop.verdict.isPresent, isFalse);
    expect(prop.verdict.actionable, isFalse);
  });

  test('a wait verdict carries what it is waiting on', () {
    final prop = PropData.fromJson(const {
      'id': 'w1',
      'player': 'Test Player',
      'sport': 'WNBA',
      'matchup': 'Dallas Wings @ Las Vegas Aces',
      'sportsbook': 'PRIZEPICKS',
      'market': 'Player Double Double',
      'line': 0.5,
      'verdict': {
        'decision': 'WAIT',
        'side': 'UNDER',
        'headline': 'WAIT ON UNDER',
        'reason': 'The edge is real, but the lineup is not confirmed.',
        'confidence': 61,
        'reasons': ['lineup_unconfirmed'],
        'recheck': 'After lineup confirmation',
        'actionable': false,
      },
    });

    expect(prop.verdict.decision, 'WAIT');
    expect(prop.verdict.recheck, 'After lineup confirmation');
    expect(prop.verdict.reasons, contains('lineup_unconfirmed'));
    // Wait is not actionable: that is the whole point of the category.
    expect(prop.verdict.actionable, isFalse);
  });

  test('malformed verdict data degrades to absent rather than throwing', () {
    for (final raw in [null, 'nonsense', 42, <String>[]]) {
      final verdict = PropVerdict.fromJson(raw);
      expect(verdict.isPresent, isFalse);
    }
  });
}
