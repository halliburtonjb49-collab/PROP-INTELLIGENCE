import '../models/saved_slip.dart';

class EvaluationCohort {
  const EvaluationCohort({
    required this.slips,
    required this.legs,
    required this.pending,
    required this.wins,
    required this.losses,
    required this.pushes,
    required this.meanAbsoluteError,
    required this.averageConfidence,
    required this.clvWins,
    required this.clvSamples,
    required this.correlatedTickets,
    required this.sourceCounts,
  });

  final List<SavedSlip> slips;
  final int legs;
  final int pending;
  final int wins;
  final int losses;
  final int pushes;
  final double? meanAbsoluteError;
  final double? averageConfidence;
  final int clvWins;
  final int clvSamples;
  final int correlatedTickets;
  final Map<String, int> sourceCounts;

  int get decisions => wins + losses;
  double? get accuracy => decisions == 0 ? null : wins * 100 / decisions;
  double? get beatCloseRate =>
      clvSamples == 0 ? null : clvWins * 100 / clvSamples;

  static EvaluationCohort fromSlips(Iterable<SavedSlip> allSlips) {
    final slips = allSlips
        .where((slip) => slip.legs.any((leg) => leg.projection != null))
        .toList(growable: false);
    var legs = 0;
    var pending = 0;
    var wins = 0;
    var losses = 0;
    var pushes = 0;
    var errorTotal = 0.0;
    var errorSamples = 0;
    var confidenceTotal = 0.0;
    var confidenceSamples = 0;
    var clvWins = 0;
    var clvSamples = 0;
    var correlatedTickets = 0;
    final sourceCounts = <String, int>{};

    for (final slip in slips) {
      final eventCounts = <String, int>{};
      for (final leg in slip.legs.where((leg) => leg.projection != null)) {
        legs += 1;
        final result = leg.resultStatus.trim().toLowerCase();
        switch (result) {
          case 'won':
          case 'win':
            wins += 1;
            break;
          case 'lost':
          case 'loss':
            losses += 1;
            break;
          case 'push':
            pushes += 1;
            break;
          default:
            pending += 1;
        }
        if (leg.resultValue != null) {
          errorTotal += (leg.resultValue! - leg.projection!).abs();
          errorSamples += 1;
        }
        if (leg.confidence != null) {
          confidenceTotal += leg.confidence!;
          confidenceSamples += 1;
        }
        if (leg.beatClosingLine != null) {
          clvSamples += 1;
          if (leg.beatClosingLine!) clvWins += 1;
        }
        final source = leg.projectionSource.trim().isEmpty
            ? 'UNSPECIFIED'
            : leg.projectionSource.trim().toUpperCase();
        sourceCounts[source] = (sourceCounts[source] ?? 0) + 1;
        final eventKey = leg.eventId.trim().isNotEmpty
            ? leg.eventId.trim()
            : '${leg.matchup.trim()}|${leg.gameStartTime.trim()}';
        eventCounts[eventKey] = (eventCounts[eventKey] ?? 0) + 1;
      }
      if (eventCounts.values.any((count) => count > 1)) correlatedTickets += 1;
    }

    return EvaluationCohort(
      slips: slips,
      legs: legs,
      pending: pending,
      wins: wins,
      losses: losses,
      pushes: pushes,
      meanAbsoluteError: errorSamples == 0 ? null : errorTotal / errorSamples,
      averageConfidence: confidenceSamples == 0
          ? null
          : confidenceTotal / confidenceSamples,
      clvWins: clvWins,
      clvSamples: clvSamples,
      correlatedTickets: correlatedTickets,
      sourceCounts: Map.unmodifiable(sourceCounts),
    );
  }
}
