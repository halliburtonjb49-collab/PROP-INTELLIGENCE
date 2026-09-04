import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/services/api_service.dart';

void main() {
  group('prop site response validation', () {
    test('keeps a PrizePicks row carrying separate provider provenance', () {
      expect(
        propMatchesSelectedSportsbook(
          selectedSportsbook: 'PRIZEPICKS',
          sportsbook: 'PrizePicks',
          sourceProvider: 'prizepicks-api',
        ),
        isTrue,
      );
    });

    test('uses provider as a fallback when the site field is absent', () {
      expect(
        propMatchesSelectedSportsbook(
          selectedSportsbook: 'DraftKings Pick6',
          sportsbook: '',
          sourceProvider: 'draftkings_pick6',
        ),
        isTrue,
      );
    });

    test('still rejects inventory from a different site', () {
      expect(
        propMatchesSelectedSportsbook(
          selectedSportsbook: 'PRIZEPICKS',
          sportsbook: 'Underdog',
          sourceProvider: 'sportsdataio',
        ),
        isFalse,
      );
    });
  });
}
