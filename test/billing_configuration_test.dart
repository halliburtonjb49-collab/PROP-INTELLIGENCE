import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/services/billing_service.dart';
import 'package:prop_intelligence/services/founding_pro_reservation_service.dart';
import 'package:prop_intelligence/services/subscription_pricing.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  test('active subscribers get a support path when the portal is missing', () {
    expect(
      subscriptionManagementUnavailableMessage(hasActivePurchase: true),
      contains('propsintell@gmail.com'),
    );
    expect(
      subscriptionManagementUnavailableMessage(hasActivePurchase: false),
      contains('No active paid subscription'),
    );
  });

  test('opens web subscription management in the current tab', () {
    expect(
      subscriptionManagementLaunchMode(isWeb: true),
      LaunchMode.platformDefault,
    );
    expect(subscriptionManagementWindowName(isWeb: true), '_self');
    expect(
      subscriptionManagementLaunchMode(isWeb: false),
      LaunchMode.externalApplication,
    );
    expect(subscriptionManagementWindowName(isWeb: false), isNull);
  });

  test('publishes the new plan prices, trials and founding-member cap', () {
    expect(SubscriptionPricing.coreMonthly, r'$24.99 / MONTH');
    expect(SubscriptionPricing.proMonthly, r'$59.99 / MONTH');
    expect(SubscriptionPricing.foundingProMonthly, r'$49.99 / MONTH');
    expect(SubscriptionPricing.coreAnnual, r'$249.99 / YEAR');
    expect(SubscriptionPricing.proAnnual, r'$599.99 / YEAR');
    expect(SubscriptionPricing.foundingProAnnual, r'$499.99 / YEAR');
    expect(SubscriptionPricing.monthlyTrialDays, 3);
    expect(SubscriptionPricing.annualTrialDays, 7);
    expect(SubscriptionPricing.foundingProMemberLimit, 100);
    expect(PurchaseTier.foundingEdge.offeringId, 'edge_founding');
    expect(PurchaseTier.foundingEdge.entitlementId, 'edge_tier');
  });

  test('accepts a reserved Founding Pro slot', () {
    expect(
      parseFoundingReservationResponse(200, '{"available":true}'),
      FoundingReservationResult.available,
    );
  });

  test('distinguishes sold-out and ineligible Founding Pro responses', () {
    expect(
      parseFoundingReservationResponse(
        200,
        '{"available":false,"soldOut":true}',
      ),
      FoundingReservationResult.soldOut,
    );
    expect(
      parseFoundingReservationResponse(200, '{"available":false}'),
      FoundingReservationResult.ineligible,
    );
  });

  test('selects a platform-specific RevenueCat public key', () {
    expect(
      selectRevenueCatPublicApiKey(
        isWeb: false,
        platform: TargetPlatform.android,
        webKey: 'web_public',
        androidKey: 'google_public',
        iosKey: 'apple_public',
        legacyKey: 'legacy_public',
      ),
      'google_public',
    );
    expect(
      selectRevenueCatPublicApiKey(
        isWeb: false,
        platform: TargetPlatform.iOS,
        webKey: 'web_public',
        androidKey: 'google_public',
        iosKey: 'apple_public',
        legacyKey: 'legacy_public',
      ),
      'apple_public',
    );
    expect(
      selectRevenueCatPublicApiKey(
        isWeb: true,
        platform: TargetPlatform.android,
        webKey: 'web_public',
        androidKey: 'google_public',
        iosKey: 'apple_public',
        legacyKey: 'legacy_public',
      ),
      'web_public',
    );
  });
}
