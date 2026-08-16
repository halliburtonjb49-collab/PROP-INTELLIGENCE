import 'package:flutter/material.dart';

import '../models/prop_data.dart';
import '../theme/app_colors.dart';

class RecommendationExplainabilityBlock extends StatelessWidget {
  const RecommendationExplainabilityBlock({
    super.key,
    required this.prop,
    this.title = 'WHY THIS PICK',
    this.expandOnTap = true,
  });

  final PropData prop;
  final String title;
  final bool expandOnTap;

  String _pct(double? value, {int decimals = 1}) {
    if (value == null) return '--';
    return '${(value * 100).toStringAsFixed(decimals)}%';
  }

  String _num(double? value, {int decimals = 1}) {
    if (value == null) return '--';
    return value.toStringAsFixed(decimals);
  }

  int _fallbackCount() {
    return [
      prop.strikeoutUsedFallbackPitcherRate,
      prop.strikeoutUsedFallbackLineupRate,
      prop.strikeoutUsedFallbackTbf,
    ].where((flag) => flag).length;
  }

  String _lineupFreshness() {
    final payload = prop.mlbProjectedLineupMatchup;
    if (payload == null) return 'unknown';
    final observedText = payload['observedAt']?.toString() ?? '';
    final observed = DateTime.tryParse(observedText);
    if (observed == null) return 'unknown';
    final minutes = DateTime.now()
        .toUtc()
        .difference(observed.toUtc())
        .inMinutes;
    if (minutes < 1) return 'just now';
    return '$minutes min';
  }

  String _coverageSummary() {
    final hasTemp = prop.temperatureF != null;
    final hasUmpire = prop.umpireKBoost != null;
    final hasSplit =
        prop.lineupKPercent != null || prop.lineupCswAgainst != null;
    final confirmed = prop.mlbProjectedLineupMatchup?['confirmed'] == true;
    final parts = <String>[];
    if (confirmed) parts.add('confirmed lineup');
    if (hasTemp) parts.add('weather present');
    if (hasUmpire) parts.add('umpire present');
    if (hasSplit) parts.add('split present');
    if (parts.isEmpty) return 'limited context';
    return parts.join(', ');
  }

  String _modelLabel() {
    if (prop.strikeoutModelMethod.trim().isNotEmpty) {
      return prop.strikeoutModelMethod;
    }
    if (prop.selectionMethod.trim().isNotEmpty) {
      return prop.selectionMethod;
    }
    return 'calibrated model';
  }

  bool _isStrikeoutProp() {
    final text = '${prop.marketKey} ${prop.market} ${prop.category}'
        .toLowerCase();
    return prop.sport.trim().toUpperCase() == 'MLB' &&
        text.contains('strikeout');
  }

  String? _weatherFactor() {
    final status = prop.weatherStatus.trim().toLowerCase();
    if (status.isEmpty || status == 'not_applicable') return null;
    final venue = prop.weatherVenue.trim();
    final venueLabel = venue.isEmpty ? '' : ' at $venue';
    if (status == 'indoor') {
      return 'Weather: indoor$venueLabel (no adjustment)';
    }
    if (status == 'roof_unknown') {
      return 'Weather: roof status unconfirmed$venueLabel (no adjustment)';
    }
    if (status != 'outdoor') {
      return 'Weather: unavailable$venueLabel (no adjustment)';
    }

    final details = <String>[];
    if (prop.temperatureF != null) {
      details.add('${prop.temperatureF!.toStringAsFixed(0)} F');
    }
    if (prop.windSpeedMph != null) {
      details.add('wind ${prop.windSpeedMph!.toStringAsFixed(0)} mph');
    }
    if (prop.precipitationProbability != null) {
      details.add('rain ${prop.precipitationProbability!.toStringAsFixed(0)}%');
    }
    final adjustment = prop.weatherMultiplier;
    final adjustmentText = (adjustment - 1).abs() < 0.001
        ? 'neutral'
        : '${adjustment.toStringAsFixed(3)}x model adjustment';
    final forecast = details.isEmpty
        ? 'forecast unavailable'
        : details.join(', ');
    return 'Weather$venueLabel: $forecast ($adjustmentText)';
  }

  /// Reasons that mean something is wrong, rather than the model declining.
  static const Set<String> _faultReasons = {
    'player_identity_unresolved',
    'insufficient_data_quality',
    'insufficient_projection_sample',
    'player_unavailable',
    'strikeout_lineup_stale',
    'strikeout_fallback_over_limit',
  };

  bool _isFault() =>
      _faultReasons.contains(prop.recommendationUnavailableReason.trim());

  /// The factors that actually drove this prop.
  ///
  /// Strikeout inputs were previously listed for every market, so a points
  /// prop showed a pitcher's strikeout rate and a park factor, both empty.
  /// An empty value reads as missing data rather than as one that never
  /// applied.
  List<String> _topFactors() {
    final weather = _weatherFactor();
    if (_isStrikeoutProp()) {
      return [
        'Pitcher K% vs lineup K%: ${_pct(prop.pitcherKPercent)} vs ${_pct(prop.lineupKPercent)}',
        'Projected batters faced: ${prop.strikeoutProjectedBattersFaced?.toString() ?? '--'}',
        'Umpire boost: ${prop.umpireKBoost == null ? '--' : '${(prop.umpireKBoost! * 100).toStringAsFixed(1)}%'}',
        'Park factor: ${_num(prop.parkKFactor, decimals: 2)}',
        ?weather,
      ];
    }
    final factors = <String>[
      'Projection ${_num(prop.projection, decimals: 2)} vs line ${_num(prop.line, decimals: 2)}',
      'Sample ${prop.projectionSampleSize} games',
    ];
    if (prop.recentHitRate != null) {
      factors.add(
        "Recent 5/10/20 blend ${prop.recentHitRate}% vs season ${prop.historicalHitRate ?? '--'}%",
      );
    }
    if (prop.paceMultiplier != null) {
      factors.add('Pace ${_num(prop.paceMultiplier, decimals: 2)}x');
    }
    if (prop.opponentDefenseMultiplier != null) {
      factors.add(
        'Opponent defence ${_num(prop.opponentDefenseMultiplier, decimals: 2)}x',
      );
    }
    if (prop.matchupMultiplier != null) {
      factors.add('Matchup ${_num(prop.matchupMultiplier, decimals: 2)}x');
    }
    if (weather != null) factors.add(weather);
    return factors;
  }

  String _actionStatus() {
    final suggestedSide = prop.proSuggestedSide;
    if (suggestedSide != null && prop.proSuggestionUsesHistoricalStats) {
      return 'PI Pick';
    }
    if (!prop.recommendationAvailable) return 'Blocked';
    final status = prop.opportunityStatus.trim().toUpperCase();
    if (status == 'READY') return 'Actionable';
    if (status == 'SYSTEM_LEAN') return 'Monitor';
    return status.isEmpty ? 'Monitor' : status;
  }

  static const Map<String, String> _reasonLabels = {
    'prop_intelligence_pass': 'model passed on this prop',
    'player_identity_unresolved': 'player could not be verified',
    'insufficient_data_quality': 'supporting data below threshold',
    'insufficient_projection_sample': 'not enough graded history',
    'player_unavailable': 'player is unavailable',
    'strikeout_lineup_stale': 'lineup data is stale',
    'strikeout_fallback_over_limit': 'too many estimated inputs',
    'probability_below_action_threshold': 'edge too small to act on',
    'uncertainty_adjusted_edge_below_threshold': 'edge inside the noise',
  };

  String _actionReason() {
    final suggestedSide = prop.proSuggestedSide;
    if (suggestedSide != null && prop.proSuggestionUsesHistoricalStats) {
      return 'projection supports $suggestedSide using the available 5/10/20 and season evidence';
    }

    if (!prop.recommendationAvailable &&
        prop.recommendationUnavailableReason.trim().isNotEmpty) {
      final raw = prop.recommendationUnavailableReason.trim();
      // Fall back to the raw token so an unmapped reason is still visible
      // rather than silently replaced with something vaguer.
      return _reasonLabels[raw] ?? raw.replaceAll('_', ' ');
    }
    if (prop.opportunityReasons.isNotEmpty) {
      return prop.opportunityReasons.first;
    }
    return prop.recommendationExplanation.trim().isEmpty
        ? 'quality gates passed'
        : prop.recommendationExplanation;
  }

  Widget _buildContent({bool expanded = false}) {
    final suggestedSide = prop.proSuggestedSide;
    final side =
        suggestedSide ??
        (prop.recommendedSide.trim().isEmpty ? 'N/A' : prop.recommendedSide);
    final trustLabel = '${prop.piTrustScore}/100 (${prop.piTrustBand})';
    final riskFlags =
        'Fallback ${_fallbackCount()}/3 | Freshness ${_lineupFreshness()} | Coverage ${_coverageSummary()}';
    final factors = _topFactors();
    final action = _actionStatus();
    // A blocked pick is the model declining, which is the safe outcome and
    // not a fault. Only a genuine data problem earns the alert colour, and
    // every colour here comes from the app palette.
    final actionColor = action == 'PI Pick'
        ? AppColors.blue
        : action == 'Actionable'
        ? AppColors.success
        : action == 'Blocked'
        ? (_isFault() ? AppColors.danger : AppColors.textMuted)
        : AppColors.gold;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF09131D),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderGold),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .5,
                  ),
                ),
              ),
              if (!expanded)
                const Text(
                  'TAP TO EXPAND',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .4,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 9),
          _row('Pick', '$side ${prop.line.toStringAsFixed(1)} ${prop.market}'),
          _row('PI Trust', trustLabel),
          _row(
            'Model',
            '${_modelLabel()} | Calibration: ${(prop.probabilityCalibrationAdjustment * 100).toStringAsFixed(1)} pts',
          ),
          _row('Top Factors', factors.join(' | ')),
          _row('Risk Flags', riskFlags),
          _row(
            'Recommendation Reason',
            prop.recommendationExplanation.trim().isEmpty
                ? prop.pickGradeExplanation
                : prop.recommendationExplanation,
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                width: 156,
                child: Text(
                  'Action Status',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  '$action (${_actionReason()})',
                  style: TextStyle(
                    color: actionColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showExpandedDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .58),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 18,
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 700, maxHeight: 760),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xC6111B26),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderGold),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'FULL PICK EXPLAINABILITY',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .4,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close, color: AppColors.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: _buildContent(expanded: true),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildContent();
    if (!expandOnTap) {
      return content;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showExpandedDialog(context),
        child: content,
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 156,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFFDCE8F4),
                fontSize: 10,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
