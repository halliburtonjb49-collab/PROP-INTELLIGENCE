import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/services/user_facing_error.dart';

void main() {
  test('network failures do not expose raw URLs or exception details', () {
    final message = userFacingLoadError(
      'ClientException: Failed to fetch https://api.example.test/private',
      noun: 'live prop feed',
    );

    expect(message, contains('temporarily unavailable'));
    expect(message, isNot(contains('https://')));
    expect(message, isNot(contains('ClientException')));
  });

  test('authentication failures give a useful recovery action', () {
    expect(
      userFacingLoadError('Exception: API returned 401'),
      contains('Sign in again'),
    );
  });

  test('unknown failures remain safe and actionable', () {
    final message = userFacingLoadError(
      'Exception: database host internal.example.test',
      noun: 'scoreboard',
    );

    expect(message, contains('Please retry'));
    expect(message, isNot(contains('internal.example.test')));
  });
}
