import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/main.dart';
import 'package:prop_intelligence/services/auth_manager.dart';

void main() {
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
  });
}
