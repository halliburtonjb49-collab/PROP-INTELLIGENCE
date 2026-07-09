class ScoreboardGame {
  const ScoreboardGame({
    required this.id,
    required this.sport,
    required this.league,
    required this.status,
    required this.detail,
    this.awayTeam = '',
    this.homeTeam = '',
    this.awayScore,
    this.homeScore,
    this.awayLogo,
    this.homeLogo,
    this.displayTime,
    this.startTime,
    this.venue,
    this.fighterOne,
    this.fighterTwo,
    this.fighterOneImage,
    this.fighterTwoImage,
    this.winner,
    this.method,
    this.round,
    this.time,
    this.weightClass,
  });

  final String id;
  final String sport;
  final String league;
  final String awayTeam;
  final String homeTeam;
  final int? awayScore;
  final int? homeScore;
  final String status;
  final String detail;
  final String? awayLogo;
  final String? homeLogo;
  final String? displayTime;
  final DateTime? startTime;
  final String? venue;
  final String? fighterOne;
  final String? fighterTwo;
  final String? fighterOneImage;
  final String? fighterTwoImage;
  final String? winner;
  final String? method;
  final int? round;
  final String? time;
  final String? weightClass;

  bool get isUfc {
    final sportValue = sport.toUpperCase();
    final leagueValue = league.toUpperCase();
    return sportValue == 'UFC' ||
        leagueValue == 'UFC' ||
        sportValue == 'MMA' ||
        leagueValue == 'MMA';
  }

  bool get isLive {
    final value = status.toUpperCase();
    return value == 'LIVE' || value == 'IN_PROGRESS' || value == 'IN PROGRESS';
  }

  bool get isFinal {
    final value = status.toUpperCase();
    return value == 'FINAL' || value == 'COMPLETED' || value == 'CLOSED';
  }

  bool get isUpcoming {
    return !isLive && !isFinal;
  }

  factory ScoreboardGame.fromJson(Map<String, dynamic> json) {
    int? parseScore(dynamic value) {
      if (value == null) {
        return null;
      }
      if (value is num) {
        return value.toInt();
      }
      return int.tryParse(value.toString());
    }

    DateTime? parseDate(dynamic value) {
      if (value == null || value.toString().isEmpty) {
        return null;
      }
      return DateTime.tryParse(value.toString());
    }

    return ScoreboardGame(
      id: (json['id'] ?? json['game_id'] ?? json['event_id'] ?? '').toString(),
      sport: (json['sport'] ?? json['sport_key'] ?? json['league'] ?? '')
          .toString()
          .toUpperCase(),
      league: (json['league'] ?? json['league_name'] ?? json['sport'] ?? '')
          .toString()
          .toUpperCase(),
      awayTeam:
          (json['away_team'] ??
                  json['awayTeam'] ??
                  json['visitor_team'] ??
                  'Away Team')
              .toString(),
      homeTeam: (json['home_team'] ?? json['homeTeam'] ?? 'Home Team')
          .toString(),
      awayScore: parseScore(
        json['away_score'] ?? json['awayScore'] ?? json['visitor_score'],
      ),
      homeScore: parseScore(json['home_score'] ?? json['homeScore']),
      status: (json['status'] ?? json['game_status'] ?? 'UPCOMING')
          .toString()
          .toUpperCase(),
      detail:
          (json['detail'] ??
                  json['status_detail'] ??
                  json['clock'] ??
                  json['period'] ??
                  '')
              .toString(),
      awayLogo: (json['away_logo'] ?? json['away_team_logo'] ?? '').toString(),
      homeLogo: (json['home_logo'] ?? json['home_team_logo'] ?? '').toString(),
      displayTime: (json['display_time'] ?? json['displayTime'] ?? '').toString(),
      startTime: parseDate(
        json['startTimeUtc'] ??
            json['start_time_utc'] ??
            json['start_time'] ??
            json['commence_time'] ??
            json['game_time'],
      ),
      venue: json['venue']?.toString(),
      fighterOne:
          (json['fighter_one'] ?? json['fighter1'] ?? json['red_corner'] ?? '')
              .toString(),
      fighterTwo:
          (json['fighter_two'] ?? json['fighter2'] ?? json['blue_corner'] ?? '')
              .toString(),
      fighterOneImage:
          (json['fighter_one_image'] ??
                  json['fighter1_image'] ??
                  json['red_corner_image'] ??
                  '')
              .toString(),
      fighterTwoImage:
          (json['fighter_two_image'] ??
                  json['fighter2_image'] ??
                  json['blue_corner_image'] ??
                  '')
              .toString(),
      winner: json['winner']?.toString(),
      method: (json['method'] ?? json['result_method'] ?? '').toString(),
      round: int.tryParse(
        (json['round'] ?? json['result_round'] ?? '').toString(),
      ),
      time: (json['time'] ?? json['result_time'] ?? '').toString(),
      weightClass: (json['weight_class'] ?? json['division'] ?? '').toString(),
    );
  }
}
