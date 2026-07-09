class SavedSlipLeg {
  final String propId;
  final String eventId;
  final String player;
  final String sport;
  final String matchup;
  final String sportsbook;
  final String market;
  final double line;
  final String side;
  final double? odds;
  final String customLabel;
  final String manualNote;
  final String gameStatus;
  final bool gameCompleted;
  final double? resultValue;
  final String resultStatus;

  const SavedSlipLeg({
    required this.propId,
    required this.eventId,
    required this.player,
    required this.sport,
    required this.matchup,
    required this.sportsbook,
    required this.market,
    required this.line,
    required this.side,
    this.odds,
    this.customLabel = '',
    this.manualNote = '',
    this.gameStatus = 'scheduled',
    this.gameCompleted = false,
    this.resultValue,
    this.resultStatus = 'pending',
  });

  factory SavedSlipLeg.fromJson(Map<String, dynamic> json) {
    return SavedSlipLeg(
      propId: json['prop_id']?.toString() ?? '',
      eventId: json['event_id']?.toString() ?? '',
      player: json['player']?.toString() ?? '',
      sport: json['sport']?.toString() ?? '',
      matchup: json['matchup']?.toString() ?? '',
      sportsbook: json['sportsbook']?.toString() ?? '',
      market: json['market']?.toString() ?? '',
      line: (json['line'] as num?)?.toDouble() ?? 0,
      side: json['side']?.toString() ?? '',
      odds: (json['odds'] as num?)?.toDouble(),
      customLabel: json['custom_label']?.toString() ?? '',
      manualNote: json['manual_note']?.toString() ?? '',
      gameStatus: json['game_status']?.toString() ?? 'scheduled',
      gameCompleted: json['game_completed'] as bool? ?? false,
      resultValue: (json['result_value'] as num?)?.toDouble(),
      resultStatus: json['result_status']?.toString() ?? 'pending',
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
