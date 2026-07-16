class PropData {
  final String id;
  final String eventId;
  final String apiSportsGameId;
  final String playerId;
  final String player;
  final String sport;
  final String matchup;
  final String sportsbook;
  final String market;
  final String marketName;
  final String statType;
  final String category;
  final String propType;
  final String displayMarket;
  final String marketKey;
  final String displayTime;
  final String startTimeUtc;
  final String gameStatus;
  final String sourceProvider;
  final String lastUpdatedUtc;
  final String sourcePlayerId;
  final String canonicalPlayerId;
  final double playerIdentityConfidence;
  final String injuryStatus;
  final String lineupStatus;
  final double? projection;
  final String recommendedSide;
  final int confidence;
  final double recommendationEdge;
  final String tier;
  final String pickText;
  final String gameTime;
  final String gameStartTime;
  final double line;
  final double openingLine;
  final double currentLine;
  final String lineMovedAtUtc;
  final String pick;
  final double edge;
  final String imagePath;
  final String customLabel;
  final String manualNote;
  final double? multiplier;
  final double? winProbability;
  final double? overOdds;
  final double? underOdds;
  final double? evPercentage;
  final double? fairProbability;
  final bool isPositiveEv;

  const PropData({
    required this.id,
    required this.eventId,
    required this.apiSportsGameId,
    required this.playerId,
    required this.player,
    required this.sport,
    required this.matchup,
    required this.sportsbook,
    required this.market,
    this.marketName = '',
    this.statType = '',
    this.category = '',
    this.propType = '',
    this.displayMarket = '',
    this.marketKey = '',
    this.displayTime = '',
    this.startTimeUtc = '',
    this.gameStatus = '',
    this.sourceProvider = '',
    this.lastUpdatedUtc = '',
    this.sourcePlayerId = '',
    this.canonicalPlayerId = '',
    this.playerIdentityConfidence = 0,
    this.injuryStatus = 'unknown',
    this.lineupStatus = 'unknown',
    this.projection,
    this.recommendedSide = 'N/A',
    this.confidence = 0,
    this.recommendationEdge = 0,
    this.tier = 'No Pick',
    this.pickText = 'No Pick',
    this.gameTime = '',
    this.gameStartTime = '',
    required this.line,
    this.openingLine = 0,
    this.currentLine = 0,
    this.lineMovedAtUtc = '',
    required this.pick,
    required this.edge,
    required this.imagePath,
    this.customLabel = '',
    this.manualNote = '',
    this.multiplier,
    this.winProbability,
    this.overOdds,
    this.underOdds,
    this.evPercentage,
    this.fairProbability,
    this.isPositiveEv = false,
  });

  static double? _safeDoubleOrNull(dynamic rawValue) {
    if (rawValue is num) {
      return rawValue.toDouble();
    }
    return double.tryParse(rawValue?.toString() ?? '');
  }

  factory PropData.fromJson(Map<String, dynamic> json) {
    return PropData(
      id:
          json['id']?.toString() ??
          json['prop_id']?.toString() ??
          json['propId']?.toString() ??
          '',
      eventId:
          json['eventId']?.toString() ?? json['event_id']?.toString() ?? '',
      apiSportsGameId:
          json['apiSportsGameId']?.toString() ??
          json['api_sports_game_id']?.toString() ??
          '',
      playerId:
          json['playerId']?.toString() ?? json['player_id']?.toString() ?? '',
      player: json['player']?.toString() ?? 'Unknown Player',
      sport: json['sport']?.toString() ?? '',
      matchup: json['matchup']?.toString() ?? '',
      sportsbook: json['sportsbook']?.toString() ?? '',
      market: json['market']?.toString() ?? '',
      marketName: json['market_name']?.toString() ?? '',
      statType: json['stat_type']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      propType: json['prop_type']?.toString() ?? '',
      displayMarket: json['display_market']?.toString() ?? '',
      marketKey:
          json['market_key']?.toString() ?? json['marketKey']?.toString() ?? '',
      displayTime:
          json['displayTime']?.toString() ??
          json['display_time']?.toString() ??
          '',
      startTimeUtc:
          json['startTimeUtc']?.toString() ??
          json['start_time_utc']?.toString() ??
          '',
      gameStatus:
          json['gameStatus']?.toString() ??
          json['game_status']?.toString() ??
          '',
      sourceProvider:
          json['sourceProvider']?.toString() ??
          json['source_provider']?.toString() ??
          '',
      lastUpdatedUtc:
          json['lastUpdatedUtc']?.toString() ??
          json['last_updated_utc']?.toString() ??
          json['sourceUpdatedUtc']?.toString() ??
          '',
      sourcePlayerId:
          json['sourcePlayerId']?.toString() ??
          json['source_player_id']?.toString() ??
          '',
      canonicalPlayerId:
          json['canonicalPlayerId']?.toString() ??
          json['canonical_player_id']?.toString() ??
          '',
      playerIdentityConfidence:
          _safeDoubleOrNull(
            json['playerIdentityConfidence'] ??
                json['player_identity_confidence'],
          ) ??
          0,
      injuryStatus:
          json['injuryStatus']?.toString() ??
          json['injury_status']?.toString() ??
          'unknown',
      lineupStatus:
          json['lineupStatus']?.toString() ??
          json['lineup_status']?.toString() ??
          'unknown',
      projection: _safeDoubleOrNull(json['projection']),
      recommendedSide:
          json['recommendedSide']?.toString() ??
          json['recommended_side']?.toString() ??
          'N/A',
      confidence: (json['confidence'] is num)
          ? (json['confidence'] as num).toInt()
          : int.tryParse('${json['confidence']}') ?? 0,
      recommendationEdge:
          _safeDoubleOrNull(
            json['recommendationEdge'] ?? json['recommendation_edge'],
          ) ??
          0,
      tier: json['tier']?.toString() ?? 'No Pick',
      pickText:
          json['pickText']?.toString() ??
          json['pick_text']?.toString() ??
          'No Pick',
      gameTime:
          json['game_time']?.toString() ?? json['gameTime']?.toString() ?? '',
      gameStartTime:
          json['startTimeUtc']?.toString() ??
          json['start_time_utc']?.toString() ??
          json['game_start_time']?.toString() ??
          json['gameStartTime']?.toString() ??
          json['commence_time']?.toString() ??
          '',
      line: (json['line'] as num?)?.toDouble() ?? 0,
      openingLine:
          _safeDoubleOrNull(json['openingLine'] ?? json['opening_line']) ??
          (json['line'] as num?)?.toDouble() ??
          0,
      currentLine:
          _safeDoubleOrNull(json['currentLine'] ?? json['current_line']) ??
          (json['line'] as num?)?.toDouble() ??
          0,
      lineMovedAtUtc:
          json['lineMovedAtUtc']?.toString() ??
          json['line_moved_at_utc']?.toString() ??
          json['line_updated_at']?.toString() ??
          '',
      pick: json['pick']?.toString() ?? '',
      edge:
          _safeDoubleOrNull(
            json['edge'] ??
                json['recommendationEdge'] ??
                json['recommendation_edge'],
          ) ??
          0,
      imagePath:
          json['player_image']?.toString() ??
          json['image_url']?.toString() ??
          json['headshot']?.toString() ??
          json['photo_url']?.toString() ??
          json['player_photo']?.toString() ??
          json['avatar']?.toString() ??
          json['image_path']?.toString() ??
          json['imagePath']?.toString() ??
          '',
      customLabel: json['custom_label']?.toString() ?? '',
      manualNote: json['manual_note']?.toString() ?? '',
      multiplier: _safeDoubleOrNull(
        json['multiplier'] ?? json['pick_multiplier'],
      ),
      winProbability: _safeDoubleOrNull(
        json['win_probability'] ?? json['winProbability'],
      ),
      overOdds: _safeDoubleOrNull(json['overOdds'] ?? json['over_odds']),
      underOdds: _safeDoubleOrNull(json['underOdds'] ?? json['under_odds']),
      evPercentage: _safeDoubleOrNull(
        json['evPercentage'] ?? json['ev_percentage'],
      ),
      fairProbability: _safeDoubleOrNull(
        json['fairProbability'] ?? json['fair_probability'],
      ),
      isPositiveEv:
          json['isPositiveEv'] == true || json['is_positive_ev'] == true,
    );
  }

  String get marketDisplay {
    final lineText = line == line.roundToDouble()
        ? line.toInt().toString()
        : line.toString();
    return '$lineText ${market.toUpperCase()}';
  }

  String get localGameTimeDisplay {
    if (displayTime.isNotEmpty) {
      return displayTime;
    }

    if (startTimeUtc.isNotEmpty) {
      final parsed = DateTime.tryParse(startTimeUtc);
      if (parsed != null) {
        final local = parsed.toLocal();
        final hour = local.hour == 0
            ? 12
            : local.hour > 12
            ? local.hour - 12
            : local.hour;
        final minute = local.minute.toString().padLeft(2, '0');
        final period = local.hour >= 12 ? 'PM' : 'AM';
        return '$hour:$minute $period';
      }
    }

    if (gameStartTime.isNotEmpty) {
      final parsed = DateTime.tryParse(gameStartTime);
      if (parsed != null) {
        final local = parsed.toLocal();
        final hour = local.hour == 0
            ? 12
            : local.hour > 12
            ? local.hour - 12
            : local.hour;
        final minute = local.minute.toString().padLeft(2, '0');
        final period = local.hour >= 12 ? 'PM' : 'AM';
        return '$hour:$minute $period';
      }
    }

    return gameTime;
  }

  String get lastUpdatedLocalDisplay {
    if (lastUpdatedUtc.isEmpty) {
      return '';
    }
    final parsed = DateTime.tryParse(lastUpdatedUtc);
    if (parsed == null) {
      return '';
    }
    final local = parsed.toLocal();
    final hour = local.hour == 0
        ? 12
        : local.hour > 12
        ? local.hour - 12
        : local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}
