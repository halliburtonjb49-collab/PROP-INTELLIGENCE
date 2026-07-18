import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/saved_slip.dart';

void main() {
  test('saved slip leg parses closing line value fields', () {
    final leg = SavedSlipLeg.fromJson({
      'prop_id': 'p1',
      'player': 'Player',
      'sport': 'NBA',
      'matchup': 'A @ B',
      'sportsbook': 'Book',
      'market': 'points',
      'line': 20.5,
      'entry_line': 20.5,
      'closing_line': 22.5,
      'closing_odds': -110,
      'line_clv': 2.0,
      'line_clv_percent': 9.7561,
      'beat_closing_line': true,
      'side': 'OVER',
    });
    expect(leg.entryLine, 20.5);
    expect(leg.closingLine, 22.5);
    expect(leg.lineClv, 2);
    expect(leg.beatClosingLine, isTrue);
  });
}
