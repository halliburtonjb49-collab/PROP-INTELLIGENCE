enum SlipRiskSeverity { info, caution, high }

class SlipRiskFinding {
  const SlipRiskFinding({
    required this.code,
    required this.title,
    required this.detail,
    required this.severity,
    this.propIds = const [],
  });

  final String code;
  final String title;
  final String detail;
  final SlipRiskSeverity severity;
  final List<String> propIds;
}

class SlipDoctorReport {
  const SlipDoctorReport({
    required this.score,
    required this.riskLevel,
    required this.findings,
    required this.weakestPropId,
  });

  final int score;
  final String riskLevel;
  final List<SlipRiskFinding> findings;
  final String weakestPropId;
  bool get healthy => findings
      .where((finding) => finding.severity == SlipRiskSeverity.high)
      .isEmpty;
}

class SlipDoctorService {
  const SlipDoctorService._();

  static String _text(Map<String, dynamic> leg, List<String> keys) {
    for (final key in keys) {
      final value = leg[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static double? _number(Map<String, dynamic> leg, List<String> keys) {
    for (final key in keys) {
      final value = leg[key];
      if (value is num) return value.toDouble();
      final parsed = double.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return null;
  }

  static String _id(Map<String, dynamic> leg) =>
      _text(leg, const ['prop_id', 'id']);
  static String _normalized(Object? value) =>
      value?.toString().trim().toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9]+'),
        '',
      ) ??
      '';

  static int trustScore(Map<String, dynamic> leg) {
    final explicit = _number(leg, const ['pi_trust_score', 'piTrustScore']);
    if (explicit != null) return explicit.round().clamp(0, 100);
    final quality = _number(leg, const [
      'data_quality_score',
      'dataQualityScore',
    ]);
    if (quality != null) {
      return (quality <= 1 ? quality * 100 : quality).round().clamp(0, 100);
    }
    return 40;
  }

  static SlipDoctorReport analyze(List<Map<String, dynamic>> legs) {
    if (legs.isEmpty) {
      return const SlipDoctorReport(
        score: 0,
        riskLevel: 'EMPTY',
        findings: [],
        weakestPropId: '',
      );
    }
    final findings = <SlipRiskFinding>[];
    final byPlayer = <String, List<Map<String, dynamic>>>{};
    final byEvent = <String, List<Map<String, dynamic>>>{};
    final byPlayerMarket = <String, List<Map<String, dynamic>>>{};
    for (final leg in legs) {
      final player = _normalized(leg['player'] ?? leg['player_name']);
      final event = _normalized(
        leg['event_id'] ?? leg['eventId'] ?? leg['matchup'],
      );
      final market = _normalized(leg['market'] ?? leg['market_type']);
      if (player.isNotEmpty) byPlayer.putIfAbsent(player, () => []).add(leg);
      if (event.isNotEmpty) byEvent.putIfAbsent(event, () => []).add(leg);
      if (player.isNotEmpty && market.isNotEmpty) {
        byPlayerMarket.putIfAbsent('$player|$market', () => []).add(leg);
      }
    }

    for (final group in byPlayer.entries.where(
      (entry) => entry.value.length > 1,
    )) {
      final player = _text(group.value.first, const ['player', 'player_name']);
      findings.add(
        SlipRiskFinding(
          code: 'same_player',
          title: 'Same-player exposure',
          detail: '${group.value.length} legs depend on $player.',
          severity: SlipRiskSeverity.high,
          propIds: group.value.map(_id).where((id) => id.isNotEmpty).toList(),
        ),
      );
    }

    for (final group in byPlayerMarket.values) {
      final sides = group
          .map((leg) => _text(leg, const ['side', 'pick']).toUpperCase())
          .where((side) => side.isNotEmpty)
          .toSet();
      if (sides.contains('OVER') && sides.contains('UNDER')) {
        findings.add(
          SlipRiskFinding(
            code: 'contradiction',
            title: 'Contradictory selections',
            detail: 'The same player and market appear on both OVER and UNDER.',
            severity: SlipRiskSeverity.high,
            propIds: group.map(_id).where((id) => id.isNotEmpty).toList(),
          ),
        );
      }
    }

    for (final group in byEvent.entries.where(
      (entry) => entry.value.length > 1,
    )) {
      final matchup = _text(group.value.first, const ['matchup']);
      final count = group.value.length;
      findings.add(
        SlipRiskFinding(
          code: count >= 3 ? 'game_concentration' : 'correlation',
          title: count >= 3
              ? 'Excessive game concentration'
              : 'Correlated game exposure',
          detail:
              '$count legs come from ${matchup.isEmpty ? 'the same event' : matchup}. Game script can move them together.',
          severity: count >= 3
              ? SlipRiskSeverity.high
              : SlipRiskSeverity.caution,
          propIds: group.value.map(_id).where((id) => id.isNotEmpty).toList(),
        ),
      );
    }

    final weak = legs
        .where(
          (leg) =>
              trustScore(leg) < 55 ||
              leg['data_stale'] == true ||
              leg['dataStale'] == true,
        )
        .toList();
    if (weak.isNotEmpty) {
      findings.add(
        SlipRiskFinding(
          code: 'weak_data',
          title: 'Weak-data props',
          detail:
              '${weak.length} leg${weak.length == 1 ? '' : 's'} fall below PI Trust 55 or use stale data.',
          severity: SlipRiskSeverity.high,
          propIds: weak.map(_id).where((id) => id.isNotEmpty).toList(),
        ),
      );
    }

    final moved = legs.where((leg) {
      final status = _text(leg, const ['movement_status']).toUpperCase();
      if (status == 'WORSE' || status == 'UNAVAILABLE') return true;
      final original = _number(leg, const ['original_line', 'opening_line']);
      final current = _number(leg, const ['current_line', 'line']);
      if (original == null || current == null) return false;
      final side = _text(leg, const ['side', 'pick']).toUpperCase();
      return (side == 'OVER' && current > original) ||
          (side == 'UNDER' && current < original);
    }).toList();
    if (moved.isNotEmpty) {
      findings.add(
        SlipRiskFinding(
          code: 'moved_line',
          title: 'Recently moved lines',
          detail:
              '${moved.length} leg${moved.length == 1 ? ' has' : 's have'} a worse or unavailable current number.',
          severity: SlipRiskSeverity.caution,
          propIds: moved.map(_id).where((id) => id.isNotEmpty).toList(),
        ),
      );
    }

    final trustAverage =
        legs.map(trustScore).reduce((a, b) => a + b) / legs.length;
    final highCount = findings
        .where((finding) => finding.severity == SlipRiskSeverity.high)
        .length;
    final cautionCount = findings
        .where((finding) => finding.severity == SlipRiskSeverity.caution)
        .length;
    final score = (trustAverage - highCount * 14 - cautionCount * 6)
        .round()
        .clamp(0, 100);
    final level = score >= 80
        ? 'LOW'
        : score >= 60
        ? 'MODERATE'
        : 'HIGH';
    final weakest = [...legs]
      ..sort((a, b) => trustScore(a).compareTo(trustScore(b)));
    return SlipDoctorReport(
      score: score,
      riskLevel: level,
      findings: findings,
      weakestPropId: _id(weakest.first),
    );
  }
}
