import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/prop_data.dart';

void main() {
  test('parses an unavailable recommendation without inventing a signal', () {
    final prop = PropData.fromJson({
      'id': 'prop-1',
      'player': 'Test Player',
      'sport': 'NBA',
      'matchup': 'Away @ Home',
      'sportsbook': 'Book',
      'market': 'Points',
      'line': 24.5,
      'pick': 'N/A',
      'edge': 0,
      'imagePath': '',
      'confidence': 0,
      'tier': 'No Pick',
      'recommendationAvailable': false,
      'recommendationUnavailableReason': 'projection_unavailable',
    });

    expect(prop.recommendationAvailable, isFalse);
    expect(prop.recommendationUnavailableReason, 'projection_unavailable');
    expect(prop.recommendedSide, 'N/A');
    expect(prop.confidence, 0);
  });
}
