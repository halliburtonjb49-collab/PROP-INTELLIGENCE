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
  final String projectionSource;
  final String projectionModelVersion;
  final int projectionSampleSize;
  final double? projectionVolatility;
  final bool projectionCalibrated;
  final String projectionLabel;
  final int? historicalHitRate;
  final String recommendedSide;
  final int confidence;
  final double recommendationEdge;
  final String tier;
  final String pickText;
  final bool recommendationAvailable;
  final String recommendationUnavailableReason;
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
    this.projectionSource = '',
    this.projectionModelVersion = '',
    this.projectionSampleSize = 0,
    this.projectionVolatility,
    this.projectionCalibrated = false,
    this.projectionLabel = '',
    this.historicalHitRate,
    this.recommendedSide = 'N/A',
    this.confidence = 0,
    this.recommendationEdge = 0,
    this.tier = 'No Pick',
    this.pickText = 'No Pick',
    this.recommendationAvailable = false,
    this.recommendationUnavailableReason = '',
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

  static double? _impliedProbability(double? odds) {
    if (odds == null || odds == 0) return null;
    if (odds > 1 && odds < 20) return 1 / odds;
    if (odds < 0) return (-odds) / ((-odds) + 100);
    if (odds >= 100) return 100 / (odds + 100);
    return null;
  }

  /// A price-derived direction that is explicitly separate from the model.
  ///
  /// This remains useful when projections are unavailable, but must never be
  /// displayed as an AI pick or model confidence score.
  String get marketLeanSide {
    final over = _impliedProbability(overOdds);
    final under = _impliedProbability(underOdds);
    if (over == null || under == null || (over - under).abs() < 0.005) {
      return 'EVEN';
    }
    return over > under ? 'OVER' : 'UNDER';
  }

  int? get marketLeanPercentage {
    final over = _impliedProbability(overOdds);
    final under = _impliedProbability(underOdds);
    if (over == null || under == null || over + under <= 0) return null;
    return ((over > under ? over : under) / (over + under) * 100).round();
  }

  /// The strongest honest directional suggestion available to Pro members.
  ///
  /// Verified model output takes precedence. When a verified projection is not
  /// available, sportsbook pricing may still provide a market-based direction,
  /// but the UI must identify that source instead of presenting it as an AI
  /// projection.
  String? get proSuggestedSide {
    final modelSide = recommendedSide.trim().toUpperCase();
    if (recommendationAvailable &&
        (modelSide == 'OVER' || modelSide == 'UNDER')) {
      return modelSide;
    }
    final marketSide = marketLeanSide;
    return marketSide == 'OVER' || marketSide == 'UNDER' ? marketSide : null;
  }

  bool get proSuggestionUsesModel =>
      recommendationAvailable &&
      (recommendedSide.trim().toUpperCase() == 'OVER' ||
          recommendedSide.trim().toUpperCase() == 'UNDER');

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
      projectionSource:
          json['projectionSource']?.toString() ??
          json['projection_source']?.toString() ??
          '',
      projectionModelVersion:
          json['projectionModelVersion']?.toString() ??
          json['projection_model_version']?.toString() ??
          '',
      projectionSampleSize:
          (json['projectionSampleSize'] as num?)?.toInt() ??
          int.tryParse('${json['projection_sample_size']}') ??
          0,
      projectionVolatility: _safeDoubleOrNull(
        json['projectionVolatility'] ?? json['projection_volatility'],
      ),
      projectionCalibrated:
          json['projectionCalibrated'] == true ||
          json['projection_calibrated'] == true,
      projectionLabel:
          json['projectionLabel']?.toString() ??
          json['projection_label']?.toString() ??
          '',
      historicalHitRate:
          (json['historicalHitRate'] as num?)?.toInt() ??
          int.tryParse('${json['historical_hit_rate']}'),
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
      recommendationAvailable:
          json['recommendationAvailable'] == true ||
          json['recommendation_available'] == true,
      recommendationUnavailableReason:
          json['recommendationUnavailableReason']?.toString() ??
          json['recommendation_unavailable_reason']?.toString() ??
          '',
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

  /// Returns true if the game has already started
  bool get gameHasStarted {
    // Check gameStatus first
    final status = gameStatus.toLowerCase();
    if (status == 'live' ||
        status == 'in progress' ||
        status == 'final' ||
        status == 'finished' ||
        status == 'completed') {
      return true;
    }

    // Parse game start time
    DateTime? gameStart;

    if (startTimeUtc.isNotEmpty) {
      gameStart = DateTime.tryParse(startTimeUtc);
    }

    if (gameStart == null && gameStartTime.isNotEmpty) {
      gameStart = DateTime.tryParse(gameStartTime);
    }

    // If we have a game start time, check if it's in the past
    if (gameStart != null) {
      return DateTime.now().toUtc().isAfter(gameStart);
    }

    // If no time info available, assume it's safe to play
    return false;
  }

  /// Returns true if the prop is selectable (game hasn't started)
  bool get isSelectable => !gameHasStarted;
}
