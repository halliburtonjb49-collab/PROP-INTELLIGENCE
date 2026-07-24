import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/services/billing_service.dart';

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
