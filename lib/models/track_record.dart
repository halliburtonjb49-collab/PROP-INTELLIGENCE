/// The model's published record, as the page reads it.
///
/// Every rate here is nullable, and that is the point. The backend withholds
/// a rate it has not earned rather than sending a zero, so absent and zero
/// must stay distinguishable all the way to the screen -- a page that renders
/// a withheld win rate as "0%" would be making the exact false claim the
/// backend refused to make.
class TrackRecordTier {
  const TrackRecordTier({
    required this.tier,
    required this.label,
    required this.sampleSize,
    required this.hits,
    this.winRate,
    this.published = false,
  });

  final String tier;
  final String label;
  final int sampleSize;
  final int hits;
  final double? winRate;
  final bool published;

  static TrackRecordTier fromJson(Map<String, dynamic> json) {
    return TrackRecordTier(
      tier: json['tier']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      sampleSize: (json['sampleSize'] as num?)?.toInt() ?? 0,
      hits: (json['hits'] as num?)?.toInt() ?? 0,
      winRate: (json['winRate'] as num?)?.toDouble(),
      published: json['published'] as bool? ?? false,
    );
  }
}

class TrackRecordClv {
  const TrackRecordClv({
    this.available = false,
    this.sampleSize = 0,
    this.beatClosingLineRate,
    this.averageLinePoints,
    this.averageOddsValuePercent,
    this.reason = '',
  });

  final bool available;
  final int sampleSize;
  final double? beatClosingLineRate;
  final double? averageLinePoints;
  final double? averageOddsValuePercent;
  final String reason;

  static TrackRecordClv fromJson(Object? raw) {
    if (raw is! Map) return const TrackRecordClv();
    final json = Map<String, dynamic>.from(raw);
    return TrackRecordClv(
      available: json['available'] as bool? ?? false,
      sampleSize: (json['sampleSize'] as num?)?.toInt() ?? 0,
      beatClosingLineRate: (json['beatClosingLineRate'] as num?)?.toDouble(),
      averageLinePoints: (json['averageLinePoints'] as num?)?.toDouble(),
      averageOddsValuePercent: (json['averageOddsValuePercent'] as num?)
          ?.toDouble(),
      reason: json['reason']?.toString() ?? '',
    );
  }
}

class TrackRecordBreakdown {
  const TrackRecordBreakdown({
    required this.key,
    required this.label,
    required this.sampleSize,
    required this.hits,
    this.winRate,
    this.simulatedRoi,
    this.published = false,
  });

  final String key;
  final String label;
  final int sampleSize;
  final int hits;
  final double? winRate;
  final double? simulatedRoi;
  final bool published;

  static TrackRecordBreakdown fromJson(Map<String, dynamic> json) {
    return TrackRecordBreakdown(
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      sampleSize: (json['sampleSize'] as num?)?.toInt() ?? 0,
      hits: (json['hits'] as num?)?.toInt() ?? 0,
      winRate: (json['winRate'] as num?)?.toDouble(),
      simulatedRoi: (json['simulatedRoi'] as num?)?.toDouble(),
      published: json['published'] as bool? ?? false,
    );
  }
}

class TrackRecordCalibrationPoint {
  const TrackRecordCalibrationPoint({
    required this.label,
    required this.sampleSize,
    this.predicted,
    this.observed,
    this.judged = false,
  });

  final String label;
  final int sampleSize;
  final double? predicted;
  final double? observed;
  final bool judged;

  static TrackRecordCalibrationPoint fromJson(Map<String, dynamic> json) {
    return TrackRecordCalibrationPoint(
      label: json['label']?.toString() ?? '',
      sampleSize: (json['sampleSize'] as num?)?.toInt() ?? 0,
      predicted: (json['predicted'] as num?)?.toDouble(),
      observed: (json['observed'] as num?)?.toDouble(),
      judged: json['judged'] as bool? ?? false,
    );
  }
}

class TrackRecord {
  const TrackRecord({
    this.generatedAt,
    this.modelVersion = '',
    this.published = false,
    this.sampleSize = 0,
    this.minimumPublishedSample = 100,
    this.gradedPicksRemaining = 0,
    this.winRate,
    this.simulatedRoi,
    this.brierScore,
    this.calibrated = false,
    this.clv = const TrackRecordClv(),
    this.tiers = const [],
    this.sports = const [],
    this.markets = const [],
    this.calibration = const [],
    this.currentStreakType = 'NONE',
    this.currentStreakLength = 0,
    this.lastGradedAt,
    this.historyPolicy = '',
    this.losingPredictionsIncluded = false,
  });

  final DateTime? generatedAt;
  final String modelVersion;
  final bool published;
  final int sampleSize;
  final int minimumPublishedSample;
  final int gradedPicksRemaining;
  final double? winRate;
  final double? simulatedRoi;
  final double? brierScore;
  final bool calibrated;
  final TrackRecordClv clv;
  final List<TrackRecordTier> tiers;
  final List<TrackRecordBreakdown> sports;
  final List<TrackRecordBreakdown> markets;
  final List<TrackRecordCalibrationPoint> calibration;
  final String currentStreakType;
  final int currentStreakLength;
  final DateTime? lastGradedAt;
  final String historyPolicy;
  final bool losingPredictionsIncluded;

  /// How far the record is toward being publishable, for a progress bar.
  double get progressToPublication {
    if (published || minimumPublishedSample <= 0) return 1;
    return (sampleSize / minimumPublishedSample).clamp(0.0, 1.0);
  }

  static TrackRecord fromJson(Map<String, dynamic> json) {
    return TrackRecord(
      generatedAt: DateTime.tryParse(json['generatedAt']?.toString() ?? ''),
      modelVersion: json['modelVersion']?.toString() ?? '',
      published: json['published'] as bool? ?? false,
      sampleSize: (json['sampleSize'] as num?)?.toInt() ?? 0,
      minimumPublishedSample:
          (json['minimumPublishedSample'] as num?)?.toInt() ?? 100,
      gradedPicksRemaining:
          (json['gradedPicksRemaining'] as num?)?.toInt() ?? 0,
      winRate: (json['winRate'] as num?)?.toDouble(),
      simulatedRoi: (json['simulatedRoi'] as num?)?.toDouble(),
      brierScore: (json['brierScore'] as num?)?.toDouble(),
      calibrated: json['calibrated'] as bool? ?? false,
      clv: TrackRecordClv.fromJson(json['closingLineValue']),
      tiers: [
        for (final entry in (json['confidenceTiers'] as List? ?? const []))
          if (entry is Map)
            TrackRecordTier.fromJson(Map<String, dynamic>.from(entry)),
      ],
      sports: [
        for (final entry in (json['sportBreakdown'] as List? ?? const []))
          if (entry is Map)
            TrackRecordBreakdown.fromJson(Map<String, dynamic>.from(entry)),
      ],
      markets: [
        for (final entry in (json['marketBreakdown'] as List? ?? const []))
          if (entry is Map)
            TrackRecordBreakdown.fromJson(Map<String, dynamic>.from(entry)),
      ],
      calibration: [
        for (final entry in (json['calibrationCurve'] as List? ?? const []))
          if (entry is Map)
            TrackRecordCalibrationPoint.fromJson(
              Map<String, dynamic>.from(entry),
            ),
      ],
      currentStreakType:
          (json['currentStreak'] as Map?)?['type']?.toString() ?? 'NONE',
      currentStreakLength:
          ((json['currentStreak'] as Map?)?['length'] as num?)?.toInt() ?? 0,
      lastGradedAt: DateTime.tryParse(json['lastGradedAt']?.toString() ?? ''),
      historyPolicy: json['historyPolicy']?.toString() ?? '',
      losingPredictionsIncluded:
          json['losingPredictionsIncluded'] as bool? ?? false,
    );
  }
}
