import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/scoreboard_game.dart';

void main() {
  test('cached MLB logos cannot render on an NFL game', () {
    final game = ScoreboardGame.fromJson(const {
      'id': 'nfl-1',
      'sport': 'NFL',
      'league': 'NFL',
      'away_team': 'San Francisco 49ers',
      'home_team': 'Los Angeles Rams',
      'away_logo': 'https://a.espncdn.com/i/teamlogos/mlb/500/tb.png',
      'home_logo': 'https://a.espncdn.com/i/teamlogos/mlb/500/atl.png',
    });

    expect(game.awayLogo, isEmpty);
    expect(game.homeLogo, isEmpty);
  });

  test('league-correct ESPN logos remain visible', () {
    final game = ScoreboardGame.fromJson(const {
      'id': 'nfl-1',
      'sport': 'NFL',
      'league': 'NFL',
      'away_team': 'San Francisco 49ers',
      'home_team': 'Los Angeles Rams',
      'away_logo': 'https://a.espncdn.com/i/teamlogos/nfl/500/sf.png',
      'home_logo': 'https://a.espncdn.com/i/teamlogos/nfl/500/lar.png',
    });

    expect(game.awayLogo, contains('/nfl/'));
    expect(game.homeLogo, contains('/nfl/'));
  });

  test('non-ESPN provider logos are not discarded', () {
    expect(
      scoreboardLogoForLeague('https://cdn.example.com/49ers.png', 'NFL'),
      'https://cdn.example.com/49ers.png',
    );
  });

  test('scoreboard parses each team moneyline and sportsbook', () {
    final game = ScoreboardGame.fromJson(const {
      'id': 'ncaaf-1',
      'sport': 'NCAAF',
      'league': 'NCAAF',
      'away_team': 'LSU Tigers',
      'home_team': 'Auburn Tigers',
      'away_moneyline': -135,
      'home_moneyline': 120,
      'away_moneyline_book': 'DraftKings',
      'home_moneyline_book': 'FanDuel',
    });

    expect(game.awayMoneyline, -135);
    expect(game.homeMoneyline, 120);
    expect(game.awayMoneylineBook, 'DraftKings');
    expect(game.homeMoneylineBook, 'FanDuel');
  });
}
