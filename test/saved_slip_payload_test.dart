import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/saved_slip.dart';
import 'package:prop_intelligence/services/api_service.dart';

void main() {
  test('saved slip response unwraps the ticket before rendering', () {
    final payload = savedSlipPayload({
      'status': 'saved',
      'slip': {
        'id': 'slip-1',
        'status': 'active',
        'stake': 10,
        'potential_payout': 20,
        'created_at': '2026-07-31T18:00:00Z',
        'legs': [
          {
            'prop_id': 'prop-1',
            'event_id': 'event-1',
            'player': 'Pitcher One',
            'sport': 'MLB',
            'matchup': 'A @ B',
            'sportsbook': 'PRIZEPICKS',
            'market': 'Pitcher Strikeouts',
            'line': 5.5,
            'side': 'OVER',
          },
        ],
      },
    });

    final slip = SavedSlip.fromJson(payload);
    expect(slip.id, 'slip-1');
    expect(slip.legs, hasLength(1));
    expect(slip.legs.single.player, 'Pitcher One');
  });
}
