class SavedSlipLeg {
  final String propId;
  final String eventId;
  final String player;
  final String imagePath;
  final String sport;
  final String matchup;
  final String sportsbook;
  final String market;
  final double line;
  final double entryLine;
  final double? closingLine;
  final double? closingOdds;
  final double? lineClv;
  final double? lineClvPercent;
  final bool? beatClosingLine;
  final String side;
  final double? odds;
  final double? projection;
  final int? confidence;
  final int piTrustScore;
  final String piTrustBand;
  final String projectionSource;
  final String projectionModelVersion;
  final bool projectionCalibrated;
  final String customLabel;
  final String manualNote;
  final String gameStatus;
  final String gameStartTime;
  final bool gameCompleted;
  final double? resultValue;
  final String resultStatus;
  final bool resultVerified;
  final String resultSource;

  const SavedSlipLeg({
    required this.propId,
    required this.eventId,
    required this.player,
    this.imagePath = '',
    required this.sport,
    required this.matchup,
    required this.sportsbook,
    required this.market,
    required this.line,
    required this.entryLine,
    this.closingLine,
    this.closingOdds,
    this.lineClv,
    this.lineClvPercent,
    this.beatClosingLine,
    required this.side,
    this.odds,
    this.projection,
    this.confidence,
    this.piTrustScore = 0,
    this.piTrustBand = 'LIMITED',
    this.projectionSource = '',
    this.projectionModelVersion = '',
    this.projectionCalibrated = false,
    this.customLabel = '',
    this.manualNote = '',
    this.gameStatus = 'scheduled',
    this.gameStartTime = '',
    this.gameCompleted = false,
    this.resultValue,
    this.resultStatus = 'pending',
    this.resultVerified = false,
    this.resultSource = '',
  });

  factory SavedSlipLeg.fromJson(Map<String, dynamic> json) {
    return SavedSlipLeg(
      propId: json['prop_id']?.toString() ?? '',
      eventId: json['event_id']?.toString() ?? '',
      player: json['player']?.toString() ?? '',
      imagePath: json['image_path']?.toString() ?? '',
      sport: json['sport']?.toString() ?? '',
      matchup: json['matchup']?.toString() ?? '',
      sportsbook: json['sportsbook']?.toString() ?? '',
      market: json['market']?.toString() ?? '',
      line: (json['line'] as num?)?.toDouble() ?? 0,
      entryLine:
          (json['entry_line'] as num?)?.toDouble() ??
          (json['line'] as num?)?.toDouble() ??
          0,
      closingLine: (json['closing_line'] as num?)?.toDouble(),
      closingOdds: (json['closing_odds'] as num?)?.toDouble(),
      lineClv: (json['line_clv'] as num?)?.toDouble(),
      lineClvPercent: (json['line_clv_percent'] as num?)?.toDouble(),
      beatClosingLine: json['beat_closing_line'] as bool?,
      side: json['side']?.toString() ?? '',
      odds: (json['odds'] as num?)?.toDouble(),
      projection: (json['projection'] as num?)?.toDouble(),
      confidence: (json['confidence'] as num?)?.toInt(),
      piTrustScore: (json['pi_trust_score'] as num?)?.toInt() ?? 0,
      piTrustBand: json['pi_trust_band']?.toString() ?? 'LIMITED',
      projectionSource: json['projection_source']?.toString() ?? '',
      projectionModelVersion:
          json['projection_model_version']?.toString() ?? '',
      projectionCalibrated: json['projection_calibrated'] as bool? ?? false,
      customLabel: json['custom_label']?.toString() ?? '',
      manualNote: json['manual_note']?.toString() ?? '',
      gameStatus: json['game_status']?.toString() ?? 'scheduled',
      gameStartTime:
          json['game_start_time']?.toString() ??
          json['start_time_utc']?.toString() ??
          '',
      gameCompleted: json['game_completed'] as bool? ?? false,
      resultValue: (json['result_value'] as num?)?.toDouble(),
      resultStatus: json['result_status']?.toString() ?? 'pending',
      resultVerified: json['result_verified'] as bool? ?? false,
      resultSource: json['result_source']?.toString() ?? '',
    );
  }
}

class SavedSlip {
  final String id;
  final String status;
  final double stake;
  final double potentialPayout;
  final DateTime? createdAt;
  final List<SavedSlipLeg> legs;

  const SavedSlip({
    required this.id,
    required this.status,
    required this.stake,
    required this.potentialPayout,
    required this.createdAt,
    required this.legs,
  });

  factory SavedSlip.fromJson(Map<String, dynamic> json) {
    final rawLegs = json['legs'];

    return SavedSlip(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'active',
      stake: (json['stake'] as num?)?.toDouble() ?? 0,
      potentialPayout: (json['potential_payout'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      legs: rawLegs is List
          ? rawLegs
                .whereType<Map<String, dynamic>>()
                .map(SavedSlipLeg.fromJson)
                .toList()
          : const [],
    );
  }
}
