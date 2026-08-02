import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/prop_data.dart';
import 'package:prop_intelligence/services/prop_market_identity.dart';

PropData _prop({required String marketKey, required String category}) {
  return PropData.fromJson({
    'id': 'test',
    'player': 'Aliyah Boston',
    'sport': 'WNBA',
    'market': category,
    'category': category,
    'marketKey': marketKey,
  });
}

void main() {
  test('canonical PRA key overrides an incorrect points label', () {
    final prop = _prop(
      marketKey: 'basketball_player_points_rebounds_assists',
      category: 'points',
    );

    expect(canonicalCategoryFromMarketKey(prop), 'PRA');
  });

  test('canonical points key remains points', () {
    final prop = _prop(marketKey: 'basketball_player_points', category: 'pra');

    expect(canonicalCategoryFromMarketKey(prop), 'POINTS');
  });
}
