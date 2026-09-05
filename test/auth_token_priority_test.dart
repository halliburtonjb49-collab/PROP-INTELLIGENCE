import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/services/api_service.dart';

void main() {
  test('a valid refreshed SDK token wins over stale website storage', () {
    expect(
      preferredAuthenticatedToken(
        currentSessionToken: 'fresh-sdk-token',
        currentSessionExpired: false,
        persistedWebsiteToken: 'stale-website-token',
      ),
      'fresh-sdk-token',
    );
  });

  test('website token restores login when the SDK session is expired', () {
    expect(
      preferredAuthenticatedToken(
        currentSessionToken: 'expired-sdk-token',
        currentSessionExpired: true,
        persistedWebsiteToken: 'website-token',
      ),
      'website-token',
    );
  });
}
