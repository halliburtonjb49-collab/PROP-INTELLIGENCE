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
    expect(prop.displayModelValue, 24.5);
    expect(prop.displayModelIsMarketBaseline, isTrue);
    expect(prop.displayModelQualifier, 'MARKET BASELINE');
  });

  test('prefers a real pre-market model value over the line baseline', () {
    final prop = PropData.fromJson({
      'id': 'prop-pre-market',
      'player': 'Test Player',
      'sport': 'NBA',
      'matchup': 'Away @ Home',
      'sportsbook': 'Book',
      'market': 'Points',
      'line': 24.5,
      'projectionPreMarket': 25.8,
      'pick': 'N/A',
      'edge': 0,
      'imagePath': '',
      'recommendationAvailable': false,
    });

    expect(prop.displayModelValue, 25.8);
    expect(prop.displayModelIsMarketBaseline, isFalse);
    expect(prop.displayModelQualifier, 'MODEL OUTPUT');
    expect(prop.recommendationAvailable, isFalse);
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

  test('uses the provider line discrepancy when model fields are omitted', () {
    final prop = PropData.fromJson({
      'id': 'prop-5',
      'player': 'Test Player',
      'sport': 'MLB',
      'matchup': 'Away @ Home',
      'sportsbook': 'Book',
      'market': 'Strikeouts',
      'line': 6.5,
      'lineDiscrepancy': -1.25,
      'edge': 0,
      'pick': 'UNDER',
      'imagePath': '',
    });

    expect(prop.calculatedEdge, 1.25);
  });

  test('derives the discrepancy from market origin and live line', () {
    final prop = PropData.fromJson({
      'id': 'prop-6',
      'player': 'Test Player',
      'sport': 'NFL',
      'matchup': 'Away @ Home',
      'sportsbook': 'Book',
      'market': 'Receiving Yards',
      'line': 67.5,
      'marketOriginLine': 70.0,
      'edge': 0,
      'pick': 'OVER',
      'imagePath': '',
    });

    expect(prop.calculatedEdge, 2.5);
  });

  test('uses model confidence for a verified Strikeout Pro Gold pick', () {
    final prop = PropData.fromJson({
      'id': 'strikeout-model',
      'player': 'Test Pitcher',
      'sport': 'MLB',
      'sportsbook': 'Book',
      'market': 'Pitcher Strikeouts',
      'line': 6.5,
      'projection': 7.4,
      'recommendedSide': 'OVER',
      'recommendationAvailable': true,
      'confidence': 72,
    });

    expect(prop.displayConfidenceRating, 72);
    expect(prop.displayConfidenceLabel, '72%');
  });

  test('uses the sportsbook rating instead of a false zero percent', () {
    final prop = PropData.fromJson({
      'id': 'strikeout-market',
      'player': 'Test Pitcher',
      'sport': 'MLB',
      'sportsbook': 'Book',
      'market': 'Pitcher Strikeouts',
      'line': 6.5,
      'overOdds': -150,
      'underOdds': 120,
      'recommendationAvailable': false,
      'confidence': 0,
    });

    expect(prop.proSuggestionUsesMarket, isTrue);
    expect(prop.displayConfidenceRating, 57);
    expect(prop.displayConfidenceLabel, '57%');
  });

  test('uses calibrated probability when a stats lean has no hit rate', () {
    final prop = PropData.fromJson({
      'id': 'strikeout-stats',
      'player': 'Test Pitcher',
      'sport': 'MLB',
      'sportsbook': 'Book',
      'market': 'Pitcher Strikeouts',
      'line': 5.0,
      'projection': 5.7,
      'uncertaintyAdjustedProbability': 0.64,
      'recommendationAvailable': false,
      'confidence': 0,
    });

    expect(prop.proSuggestionUsesHistoricalStats, isTrue);
    expect(prop.displayConfidenceRating, 64);
    expect(prop.displayConfidenceLabel, '64%');
  });

  test('separates the model estimate from the conservative risk floor', () {
    final prop = PropData.fromJson({
      'id': 'wnba-model-estimate',
      'player': 'Test Guard',
      'sport': 'WNBA',
      'sportsbook': 'PrizePicks',
      'market': 'Fantasy Score',
      'line': 30.5,
      'recommendedSide': 'UNDER',
      'recommendationAvailable': true,
      'fairProbability': 0.62,
      'uncertaintyAdjustedProbability': 0.42,
      'confidence': 42,
    });

    expect(prop.displayModelEstimateRating, 62);
    expect(prop.displayRiskFloorRating, 42);
    expect(prop.displayConfidenceRating, 42);
  });
}
