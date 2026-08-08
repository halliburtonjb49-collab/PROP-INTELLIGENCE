/// Today's board, reduced to what a person needs before deciding anything.
///
/// Every field degrades to an honest empty rather than a zero. A briefing
/// that renders "0 plays" when it failed to load is indistinguishable from a
/// briefing that correctly found none, and those mean opposite things.
class BriefingPlay {
  const BriefingPlay({
    this.propId = '',
    this.player = '',
    this.sport = '',
    this.market = '',
    this.line,
    this.side = '',
    this.decision = '',
    this.headline = '',
    this.reason = '',
    this.confidence = 0,
    this.sportsbook = '',
    this.expectedValuePercent,
  });

  final String propId;
  final String player;
  final String sport;
  final String market;
  final double? line;
  final String side;
  final String decision;
  final String headline;
  final String reason;
  final int confidence;
  final String sportsbook;
  final double? expectedValuePercent;

  static BriefingPlay fromJson(Object? raw) {
    if (raw is! Map) return const BriefingPlay();
    final json = Map<String, dynamic>.from(raw);
    final line = json['line'];
    final ev = json['expectedValuePercent'];
    return BriefingPlay(
      propId: json['propId']?.toString() ?? '',
      player: json['player']?.toString() ?? '',
      sport: json['sport']?.toString() ?? '',
      market: json['market']?.toString() ?? '',
      line: line is num ? line.toDouble() : null,
      side: json['side']?.toString() ?? '',
      decision: json['decision']?.toString() ?? '',
      headline: json['headline']?.toString() ?? '',
      reason: json['reason']?.toString() ?? '',
      confidence: (json['confidence'] as num?)?.toInt() ?? 0,
      sportsbook: json['sportsbook']?.toString() ?? '',
      expectedValuePercent: ev is num ? ev.toDouble() : null,
    );
  }
}

class DailyBriefing {
  const DailyBriefing({
    this.generatedAt = '',
    this.propsOnBoard = 0,
    this.sportsCovered = const [],
    this.actionable = 0,
    this.quietDay = true,
    this.summary = '',
    this.leadPlays = const [],
    this.caveats = const [],
    this.loaded = false,
  });

  final String generatedAt;
  final int propsOnBoard;
  final List<String> sportsCovered;
  final int actionable;
  final bool quietDay;
  final String summary;
  final List<BriefingPlay> leadPlays;
  final List<String> caveats;

  /// Whether a briefing was actually received. A failed load must not be
  /// able to render as a quiet day -- "nothing clears the bar" is a claim,
  /// and it should only ever be made on evidence.
  final bool loaded;

  static DailyBriefing fromJson(Object? raw) {
    if (raw is! Map) return const DailyBriefing();
    final json = Map<String, dynamic>.from(raw);
    return DailyBriefing(
      generatedAt: json['generatedAt']?.toString() ?? '',
      propsOnBoard: (json['propsOnBoard'] as num?)?.toInt() ?? 0,
      sportsCovered: (json['sportsCovered'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      actionable: (json['actionable'] as num?)?.toInt() ?? 0,
      quietDay: json['quietDay'] as bool? ?? true,
      summary: json['summary']?.toString() ?? '',
      leadPlays: (json['leadPlays'] as List? ?? const [])
          .map(BriefingPlay.fromJson)
          .toList(growable: false),
      caveats: (json['caveats'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      loaded: true,
    );
  }
}
