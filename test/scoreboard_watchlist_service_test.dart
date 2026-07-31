import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/scoreboard_game.dart';
import 'package:prop_intelligence/services/scoreboard_watchlist_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

ScoreboardGame game({
  int away = 0,
  int home = 0,
  String status = 'LIVE',
  String detail = 'Q4 1:00',
}) => ScoreboardGame(
  id: 'game-1',
  sport: 'NBA',
  league: 'NBA',
  status: status,
  detail: detail,
  awayTeam: 'Away',
  homeTeam: 'Home',
  awayScore: away,
  homeScore: home,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persists watched games and alerts when the score changes', () async {
    final service = ScoreboardWatchlistService.forTesting();
    await service.toggle(game(away: 10, home: 9));

    service.processGames([game(away: 12, home: 9)]);

    expect(service.isWatching('game-1'), isTrue);
    expect(service.latestAlert.value?.type, ScoreboardWatchAlertType.score);
    expect(service.latestAlert.value?.message, contains('12-9'));
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getStringList('scoreboard_watched_game_ids'),
      contains('game-1'),
    );
  });

  test('alerts when a watched game enters extended play', () async {
    final service = ScoreboardWatchlistService.forTesting();
    await service.toggle(game(detail: 'End Q4'));

    service.processGames([game(detail: 'OT 4:30')]);

    expect(
      service.latestAlert.value?.type,
      ScoreboardWatchAlertType.extendedPlay,
    );
  });

  test('announces the winner when a watched game becomes final', () async {
    final service = ScoreboardWatchlistService.forTesting();
    await service.toggle(game(away: 98, home: 99));

    service.processGames([
      game(away: 101, home: 105, status: 'FINAL', detail: 'Final'),
    ]);

    expect(
      service.latestAlert.value?.type,
      ScoreboardWatchAlertType.finalResult,
    );
    expect(service.latestAlert.value?.message, contains('Home won 105-101'));
  });
}
