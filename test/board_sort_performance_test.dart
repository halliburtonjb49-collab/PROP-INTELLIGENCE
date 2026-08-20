import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/prop_data.dart';
import 'package:prop_intelligence/services/prop_board_engine.dart';

void main() {
  test('a full board filters and sorts without stalling a frame', () {
    // Every ordering starts with game time, and the comparator used to parse
    // two date strings per comparison: roughly 350,000 parses for a board
    // this size, on every rebuild. A full board took 359ms, so favouriting a
    // prop or switching books froze the screen for about twenty frames.
    // Precomputing the start time on the prepared prop took it to 13ms.
    final props = List.generate(13000, (i) {
      return PropData.fromJson({
        'id': 'p$i',
        'player': 'Player $i',
        'sport': i.isEven ? 'MLB' : 'WNBA',
        'matchup': 'A @ B',
        'sportsbook': 'DRAFTKINGS',
        'market': 'Points',
        'line': 10.0 + (i % 7),
        'projection': 12.0,
        'startTimeUtc': '2026-08-2${i % 9}T18:00:00Z',
        'piTrustScore': i % 100,
      });
    });
    final prepared = prepareBoardProps(props);

    final watch = Stopwatch()..start();
    for (var run = 0; run < 10; run++) {
      filterAndSortBoardProps(
        prepared,
        selectedSport: 'ALL',
        selectedSite: 'ALL',
        searchQuery: '',
        verdictFilter: 'ALL',
        sortBy: 'trust',
      );
    }
    watch.stop();

    final perRun = watch.elapsedMilliseconds / 10;
    // Generous against a slow CI box while still catching the regression
    // this exists to prevent: the old code was an order of magnitude worse.
    expect(
      perRun,
      lessThan(120),
      reason: 'filter+sort of ${props.length} props took ${perRun}ms',
    );
  });
}
