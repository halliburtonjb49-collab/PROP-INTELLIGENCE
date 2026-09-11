import 'dart:convert';

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

  test('expired persisted JWT is refreshed before a protected request', () {
    String token(int expiresAt) {
      final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'none'})));
      final payload = base64Url.encode(
        utf8.encode(jsonEncode({'exp': expiresAt})),
      );
      return '$header.$payload.signature';
    }

    final now = DateTime.utc(2026, 9, 11, 12);
    expect(
      authenticatedJwtNeedsRefresh(
        token(
          now.subtract(const Duration(seconds: 1)).millisecondsSinceEpoch ~/
              1000,
        ),
        now: now,
      ),
      isTrue,
    );
    expect(
      authenticatedJwtNeedsRefresh(
        token(
          now.add(const Duration(minutes: 5)).millisecondsSinceEpoch ~/ 1000,
        ),
        now: now,
      ),
      isFalse,
    );
  });
}
