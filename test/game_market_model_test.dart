import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/game_market.dart';

void main() {
  test('game market parses Shin and Dixon-Coles probability metadata', () {
    final event = GameMarketEvent.fromJson({
      'id': 'game-1',
      'sport': 'EPL',
      'bookmakers': [
        {
          'markets': {
            'totals': [
              {
                'name': 'Over',
                'price': -110,
                'point': 2.5,
                'impliedProbability': .5238,
                'fairProbability': .5,
                'devigMethod': 'shin',
              },
            ],
          },
        },
      ],
      'dixonColes': {
        'overProbability': .47,
        'underProbability': .53,
        'method': 'dixon-coles',
      },
    });

    final outcome = event.bookmakers.single.markets['totals']!.single;
    expect(outcome.fairProbability, .5);
    expect(outcome.devigMethod, 'shin');
    expect(event.dixonColes?['method'], 'dixon-coles');
  });
}
