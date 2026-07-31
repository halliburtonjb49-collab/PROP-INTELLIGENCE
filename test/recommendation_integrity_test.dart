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
    expect(prop.calculatedEdge, isNull);
  });

  test('recalculates card edge from projection and current line', () {
    final prop = PropData.fromJson({
      'id': 'prop-2',
      'player': 'Test Player',
      'sport': 'NBA',
      'matchup': 'Away @ Home',
      'sportsbook': 'Book',
      'market': 'Points',
      'line': 24.5,
      'projection': 27.2,
      // A cached backend edge must not override the live projection gap.
      'edge': 0,
      'pick': 'OVER',
      'imagePath': '',
    });

    expect(prop.calculatedEdge, closeTo(2.7, 0.0001));
  });

  test('shows a verified recommendation edge when projection is omitted', () {
    final prop = PropData.fromJson({
      'id': 'prop-3',
      'player': 'Test Player',
      'sport': 'NFL',
      'matchup': 'Away @ Home',
      'sportsbook': 'Book',
      'market': 'Passing Yards',
      'line': 255.5,
      'recommendationEdge': 6.25,
      'edge': 0,
      'pick': 'OVER',
      'imagePath': '',
    });

    expect(prop.calculatedEdge, 6.25);
  });

  test('supports legacy backend edge when projection is omitted', () {
    final prop = PropData.fromJson({
      'id': 'prop-4',
      'player': 'Test Player',
      'sport': 'MLB',
      'matchup': 'Away @ Home',
      'sportsbook': 'Book',
      'market': 'Strikeouts',
      'line': 5.5,
      'edge': 1.75,
      'pick': 'UNDER',
      'imagePath': '',
    });

    expect(prop.calculatedEdge, 1.75);
  });
}
