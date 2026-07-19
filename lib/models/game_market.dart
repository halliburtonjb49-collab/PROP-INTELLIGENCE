class GameMarketOutcome {
  final String name;
  final int price;
  final double? point;

  const GameMarketOutcome({
    required this.name,
    required this.price,
    required this.point,
  });

  factory GameMarketOutcome.fromJson(Map<String, dynamic> json) {
    final rawPrice = json['price'];
    return GameMarketOutcome(
      name: json['name']?.toString() ?? '',
      price: rawPrice is num
          ? rawPrice.round()
          : int.tryParse('$rawPrice') ?? 0,
      point: json['point'] is num ? (json['point'] as num).toDouble() : null,
    );
  }
}

class SportsbookGameMarkets {
  final String key;
  final String title;
  final DateTime? lastUpdate;
  final Map<String, List<GameMarketOutcome>> markets;

  const SportsbookGameMarkets({
    required this.key,
    required this.title,
    required this.lastUpdate,
    required this.markets,
  });

  factory SportsbookGameMarkets.fromJson(Map<String, dynamic> json) {
    final rawMarkets = json['markets'];
    final parsed = <String, List<GameMarketOutcome>>{};
    if (rawMarkets is Map) {
      for (final entry in rawMarkets.entries) {
        final values = entry.value;
        if (values is List) {
          parsed[entry.key.toString()] = values
              .whereType<Map>()
              .map(
                (value) => GameMarketOutcome.fromJson(
                  Map<String, dynamic>.from(value),
                ),
              )
              .toList(growable: false);
        }
      }
    }
    return SportsbookGameMarkets(
      key: json['key']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Sportsbook',
      lastUpdate: DateTime.tryParse(json['lastUpdate']?.toString() ?? ''),
      markets: parsed,
    );
  }
}

class GameMarketEvent {
  final String id;
  final String sport;
  final String league;
  final String homeTeam;
  final String awayTeam;
  final DateTime? commenceTime;
  final List<SportsbookGameMarkets> bookmakers;

  const GameMarketEvent({
    required this.id,
    required this.sport,
    required this.league,
    required this.homeTeam,
    required this.awayTeam,
    required this.commenceTime,
    required this.bookmakers,
  });

  factory GameMarketEvent.fromJson(Map<String, dynamic> json) {
    return GameMarketEvent(
      id: json['id']?.toString() ?? '',
      sport: json['sport']?.toString() ?? '',
      league: json['league']?.toString() ?? '',
      homeTeam: json['homeTeam']?.toString() ?? 'Home',
      awayTeam: json['awayTeam']?.toString() ?? 'Away',
      commenceTime: DateTime.tryParse(json['commenceTime']?.toString() ?? ''),
      bookmakers: (json['bookmakers'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (value) => SportsbookGameMarkets.fromJson(
              Map<String, dynamic>.from(value),
            ),
          )
          .toList(growable: false),
    );
  }
}

class GameMarketFeed {
  final String sport;
  final DateTime? updatedAt;
  final bool cached;
  final bool stale;
  final List<GameMarketEvent> events;

  const GameMarketFeed({
    required this.sport,
    required this.updatedAt,
    required this.cached,
    required this.stale,
    required this.events,
  });

  factory GameMarketFeed.fromJson(Map<String, dynamic> json) {
    return GameMarketFeed(
      sport: json['sport']?.toString() ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      cached: json['cached'] == true,
      stale: json['stale'] == true,
      events: (json['events'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (value) =>
                GameMarketEvent.fromJson(Map<String, dynamic>.from(value)),
          )
          .toList(growable: false),
    );
  }
}
