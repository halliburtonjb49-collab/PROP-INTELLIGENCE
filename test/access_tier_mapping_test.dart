import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/main.dart';
import 'package:prop_intelligence/services/auth_manager.dart';
import 'package:prop_intelligence/models/prop_data.dart';
import 'package:prop_intelligence/models/slip_selection.dart';

void main() {
  test('feature badges reflect the minimum tier required by the feature', () {
    expect(
      displayedTierForBadge(
        requiredTier: SubscriptionTier.core,
        hasEdgeAccess: true,
      ),
      SubscriptionTier.core,
    );
    expect(
      displayedTierForBadge(
        requiredTier: SubscriptionTier.core,
        hasEdgeAccess: false,
      ),
      SubscriptionTier.core,
    );
  });

  test('upgradeable Core pages identify their Pro experience', () {
    expect(
      displayedTierForBadge(
        requiredTier: SubscriptionTier.core,
        hasEdgeAccess: true,
        hasProUpgrade: true,
      ),
      SubscriptionTier.edge,
    );
    expect(
      displayedTierForBadge(
        requiredTier: SubscriptionTier.core,
        hasEdgeAccess: false,
        hasProUpgrade: true,
      ),
      SubscriptionTier.core,
    );
  });

  test('Core contains only standard research and organization tools', () {
    expect(requiredTierForPage(AppPage.gameMarkets), SubscriptionTier.core);
    expect(requiredTierForPage(AppPage.propBuilder), SubscriptionTier.core);
    expect(requiredTierForPage(AppPage.watchlist), SubscriptionTier.core);
    expect(requiredTierForPage(AppPage.analytics), SubscriptionTier.core);
    expect(requiredTierForPage(AppPage.lineMovement), SubscriptionTier.core);
    expect(requiredTierForPage(AppPage.pastSlipHistory), SubscriptionTier.core);
  });

  test('advanced intelligence tools require Pro', () {
    for (final page in [
      AppPage.propAlerts,
      AppPage.builderPerformance,
      AppPage.evScanner,
      AppPage.strikeoutProGold,
      AppPage.intelligenceLab,
    ]) {
      expect(
        requiredTierForPage(page),
        SubscriptionTier.edge,
        reason: page.name,
      );
    }
  });

  test('public workspace pages have no feature-tier gate', () {
    expect(requiredTierForPage(AppPage.board), isNull);
    expect(requiredTierForPage(AppPage.scoreboard), isNull);
    expect(requiredTierForPage(AppPage.searchPlayers), isNull);
    expect(requiredTierForPage(AppPage.propChat), isNull);
  });

  test('market lean derives direction without inventing a model pick', () {
    const overLean = PropData(
      id: 'over',
      eventId: '',
      apiSportsGameId: '',
      playerId: '',
      player: 'Player',
      sport: 'NBA',
      matchup: '',
      sportsbook: 'Book',
      market: 'Points',
      line: 20.5,
      pick: 'N/A',
      edge: 0,
      imagePath: '',
      overOdds: -125,
      underOdds: 105,
    );
    const even = PropData(
      id: 'even',
      eventId: '',
      apiSportsGameId: '',
      playerId: '',
      player: 'Player',
      sport: 'NBA',
      matchup: '',
      sportsbook: 'Book',
      market: 'Points',
      line: 20.5,
      pick: 'N/A',
      edge: 0,
      imagePath: '',
      overOdds: -110,
      underOdds: -110,
    );

    expect(overLean.marketLeanSide, 'OVER');
    expect(overLean.marketLeanPercentage, greaterThan(50));
    expect(overLean.recommendationAvailable, isFalse);
    expect(overLean.proSuggestedSide, 'OVER');
    expect(overLean.proSuggestionUsesModel, isFalse);
    expect(even.marketLeanSide, 'EVEN');
    expect(even.proSuggestedSide, isNull);
  });

  test('Pro suggestion prioritizes a verified model direction', () {
    const prop = PropData(
      id: 'model',
      eventId: '',
      apiSportsGameId: '',
      playerId: 'player',
      player: 'Player',
      sport: 'NBA',
      matchup: '',
      sportsbook: 'Book',
      market: 'Points',
      line: 20.5,
      pick: 'UNDER',
      edge: 2.5,
      imagePath: '',
      projection: 18,
      recommendedSide: 'UNDER',
      recommendationAvailable: true,
      overOdds: -130,
      underOdds: 110,
    );

    expect(prop.marketLeanSide, 'OVER');
    expect(prop.proSuggestedSide, 'UNDER');
    expect(prop.proSuggestionUsesModel, isTrue);
  });

  test('baseline projection metadata remains visible to the client', () {
    final prop = PropData.fromJson({
      'id': 'baseline',
      'eventId': 'event',
      'apiSportsGameId': '',
      'playerId': 'player',
      'player': 'Player',
      'sport': 'NBA',
      'matchup': 'A @ B',
      'sportsbook': 'Book',
      'market': 'Points',
      'line': 20.5,
      'pick': 'OVER',
      'edge': 1.4,
      'imagePath': '',
      'projection': 21.9,
      'projectionSource': 'historical-game-logs',
      'projectionModelVersion': 'baseline-v1',
      'projectionSampleSize': 15,
      'projectionVolatility': 4.2,
      'projectionCalibrated': false,
      'projectionLabel': 'Baseline historical model',
      'historicalHitRate': 67,
    });

    expect(prop.projectionModelVersion, 'baseline-v1');
    expect(prop.projectionSampleSize, 15);
    expect(prop.projectionVolatility, 4.2);
    expect(prop.projectionCalibrated, isFalse);
    expect(prop.historicalHitRate, 67);
  });

  test('board intelligence follows active selections before card focus', () {
    const focused = PropData(
      id: 'focused',
      eventId: '',
      apiSportsGameId: '',
      playerId: '',
      player: 'Focused Player',
      sport: 'NBA',
      matchup: '',
      sportsbook: 'Book',
      market: 'Points',
      line: 20.5,
      pick: 'N/A',
      edge: 0,
      imagePath: '',
    );
    const selected = PropData(
      id: 'selected',
      eventId: '',
      apiSportsGameId: '',
      playerId: '',
      player: 'Selected Player',
      sport: 'NBA',
      matchup: '',
      sportsbook: 'Book',
      market: 'Assists',
      line: 5.5,
      pick: 'OVER',
      edge: 2,
      imagePath: '',
    );

    final scope = boardIntelligenceScope(
      selections: const [SlipSelection(prop: selected, side: PickSide.over)],
      visibleProps: const [focused, selected],
      focusedProp: focused,
    );

    expect(scope, hasLength(1));
    expect(scope.single.id, 'selected');
  });
}
