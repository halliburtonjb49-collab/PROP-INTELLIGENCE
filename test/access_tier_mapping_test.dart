import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/main.dart' show boardIntelligenceScope;
import 'package:prop_intelligence/navigation/app_navigation.dart';
import 'package:prop_intelligence/services/recommendation_access.dart';
import 'package:prop_intelligence/services/auth_manager.dart';
import 'package:prop_intelligence/models/prop_data.dart';
import 'package:prop_intelligence/models/slip_selection.dart';

void main() {
  test('system OVER/UNDER direction is available only with Pro access', () {
    expect(canShowSystemRecommendation(hasEdgeAccess: false), isFalse);
    expect(canShowSystemRecommendation(hasEdgeAccess: true), isTrue);
    expect(
      gatedSystemRecommendationSide(
        hasEdgeAccess: false,
        recommendation: 'OVER',
      ),
      isNull,
    );
    expect(
      gatedSystemRecommendationSide(
        hasEdgeAccess: true,
        recommendation: 'under',
      ),
      'UNDER',
    );
  });
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
    expect(
      requiredTierForPage(AppPage.scoreboardWatchlist),
      SubscriptionTier.edge,
    );
    expect(requiredTierForPage(AppPage.pastSlipHistory), SubscriptionTier.core);
  });

  test('advanced intelligence tools require Pro', () {
    for (final page in [
      AppPage.propAlerts,
      AppPage.builderPerformance,
      AppPage.evScanner,
      AppPage.strikeoutProGold,
      AppPage.intelligenceLab,
      AppPage.injuryImpact,
      AppPage.refereeTracker,
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
    expect(requiredTierForPage(AppPage.propChat), SubscriptionTier.core);
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
    expect(even.proSuggestedSide, 'UNDER');
    expect(even.proSuggestionUsesResearchFallback, isTrue);
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

  test('historical projection provides a definite Pro PI Pick direction', () {
    const prop = PropData(
      id: 'historical-lean',
      eventId: '',
      apiSportsGameId: '',
      playerId: 'player',
      player: 'Player',
      sport: 'SOCCER',
      matchup: '',
      sportsbook: 'Book',
      market: 'Shots',
      line: 2.5,
      pick: 'N/A',
      edge: 0,
      imagePath: '',
      projection: 3.1,
      projectionSource: 'historical-game-logs',
      projectionSampleSize: 10,
      recommendationAvailable: false,
      recommendationUnavailableReason: 'model_signal_below_threshold',
      overOdds: 120,
      underOdds: -140,
    );

    expect(prop.marketLeanSide, 'UNDER');
    expect(prop.proSuggestedSide, 'OVER');
    expect(prop.proSuggestionUsesModel, isFalse);
    expect(prop.proSuggestionUsesHistoricalStats, isTrue);
    expect(prop.proSuggestionUsesMarket, isFalse);
  });

  test('pre-market projection provides a definite Pro PI Pick direction', () {
    const prop = PropData(
      id: 'pre-market',
      eventId: '',
      apiSportsGameId: '',
      playerId: 'player',
      player: 'Player',
      sport: 'MLB',
      matchup: '',
      sportsbook: 'Book',
      market: 'Pitcher Strikeouts',
      line: 4.5,
      pick: 'N/A',
      edge: 0,
      imagePath: '',
      projectionPreMarket: 5.2,
      recommendationAvailable: false,
    );

    expect(prop.proSuggestedSide, 'OVER');
    expect(prop.proSuggestionUsesHistoricalStats, isTrue);
    expect(prop.proSuggestionUsesResearchFallback, isFalse);
  });

  test('Pro always gets a disclosed stable direction without model evidence', () {
    const prop = PropData(
      id: 'unmodeled',
      eventId: '',
      apiSportsGameId: '',
      playerId: 'player',
      player: 'Player',
      sport: 'MLB',
      matchup: '',
      sportsbook: 'Book',
      market: 'Pitcher Strikeouts',
      line: 4.5,
      pick: 'N/A',
      edge: 0,
      imagePath: '',
      recommendationAvailable: false,
      recentHitRate: 62,
      verdict: PropVerdict(
        decision: 'PASS',
        headline: 'TAKE A CHANCE - NOT BACKED',
      ),
    );

    expect(prop.proSuggestedSide, 'OVER');
    expect(prop.proSuggestionUsesResearchFallback, isTrue);
  });

  test('PI verdict side overrides a conflicting fallback projection pick', () {
    final prop = PropData.fromJson(const {
      'id': 'verdict-wins',
      'player': 'Player',
      'sport': 'MLB',
      'matchup': 'A @ B',
      'sportsbook': 'Book',
      'market': 'Pitcher Strikeouts',
      'line': 4.5,
      'projection': 4.8,
      'recommendationAvailable': false,
      'verdict': {
        'decision': 'SHOP',
        'side': 'UNDER',
        'headline': 'CHECK OTHER BOOKS - UNDER',
        'actionable': true,
      },
    });

    expect(prop.proSuggestionUsesHistoricalStats, isTrue);
    expect(prop.proSuggestedSide, 'UNDER');
  });

  test('PASS verdict keeps its non-actionable Pro research direction', () {
    final prop = PropData.fromJson(const {
      'id': 'not-backed',
      'player': 'Player',
      'sport': 'MLB',
      'matchup': 'A @ B',
      'sportsbook': 'Book',
      'market': 'Batter Hits',
      'line': 0.5,
      'projection': 0.8,
      'verdict': {
        'decision': 'PASS',
        'side': 'OVER',
        'headline': 'TAKE A CHANCE - NOT BACKED',
        'actionable': false,
      },
    });

    expect(prop.proSuggestionUsesHistoricalStats, isTrue);
    expect(prop.proSuggestedSide, 'OVER');
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
      'temperatureF': 72,
      'apparentTemperatureF': 68,
      'precipitationProbability': 35,
      'windSpeedMph': 12,
      'windGustMph': 18,
      'weatherCode': 3,
      'weatherMultiplier': 0.98,
      'weatherStatus': 'outdoor',
      'weatherVenue': 'Buffalo Bills stadium',
      'weatherSource': 'open-meteo',
      'weatherForecastForUtc': '2026-08-16T17:25:00+00:00',
    });

    expect(prop.projectionModelVersion, 'baseline-v1');
    expect(prop.projectionSampleSize, 15);
    expect(prop.projectionVolatility, 4.2);
    expect(prop.projectionCalibrated, isFalse);
    expect(prop.historicalHitRate, 67);
    expect(prop.temperatureF, 72);
    expect(prop.apparentTemperatureF, 68);
    expect(prop.precipitationProbability, 35);
    expect(prop.windSpeedMph, 12);
    expect(prop.windGustMph, 18);
    expect(prop.weatherCode, 3);
    expect(prop.weatherMultiplier, 0.98);
    expect(prop.weatherStatus, 'outdoor');
    expect(prop.weatherVenue, 'Buffalo Bills stadium');
    expect(prop.weatherSource, 'open-meteo');
    expect(prop.weatherForecastForUtc, '2026-08-16T17:25:00+00:00');
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

  test('navigation metadata covers every application page', () {
    for (final page in AppPage.values) {
      expect(appPageTitle(page), isNotEmpty, reason: page.name);
      expect(appPageSubtitle(page), isNotEmpty, reason: page.name);
      expect(appPageHowTo(page), isNotEmpty, reason: page.name);
    }
  });

  test('navigation groups do not repeat destinations', () {
    final pages = appNavigationGroups
        .expand((group) => group.$3)
        .map((entry) => entry.$2)
        .toList(growable: false);
    expect(pages.toSet().length, pages.length);
    expect(
      pages,
      containsAll(<AppPage>[
        AppPage.board,
        AppPage.propBuilder,
        AppPage.scoreboard,
        AppPage.trackRecord,
        AppPage.gameMarkets,
      ]),
    );
  });
}
