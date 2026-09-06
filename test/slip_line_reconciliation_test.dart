import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/prop_data.dart';
import 'package:prop_intelligence/services/slip_manager.dart';

void main() {
  tearDown(SlipManager.clearAllSlips);

  test('market refresh never replaces the ticket original line', () {
    SlipManager.selectedProps.value = [
      {
        'id': 'prop-1',
        'prop_id': 'prop-1',
        'player_name': 'Player One',
        'market_type': 'Hits',
        'sportsbook': 'PRIZEPICKS',
        'line': 1.5,
        'original_line': 1.5,
      },
    ];
    final latest = PropData.fromJson(const {
      'id': 'prop-1',
      'event_id': 'event-1',
      'player_id': 'player-1',
      'player_name': 'Player One',
      'sport': 'MLB',
      'matchup': 'A @ B',
      'sportsbook': 'PRIZEPICKS',
      'market_type': 'Hits',
      'line': 2.5,
      'pick': 'UNDER',
      'edge': 3,
      'image_path': '',
    });

    SlipManager.refreshSelectedPropsFromRows([latest]);

    final ticket = SlipManager.selectedProps.value.single;
    expect(ticket['original_line'], 1.5);
    expect(ticket['line'], 1.5);
    expect(ticket['current_line'], 2.5);
  });
}
