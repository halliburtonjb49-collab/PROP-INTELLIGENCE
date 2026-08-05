import 'package:flutter/material.dart';

import '../models/prop_data.dart';
import '../theme/app_colors.dart';

class RecommendationExplainabilityBlock extends StatelessWidget {
  const RecommendationExplainabilityBlock({
    super.key,
    required this.prop,
    this.title = 'WHY THIS PICK',
  });

  final PropData prop;
  final String title;

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

  String _actionStatus() {
    if (!prop.recommendationAvailable) return 'Blocked';
    final status = prop.opportunityStatus.trim().toUpperCase();
    if (status == 'READY') return 'Actionable';
    if (status == 'SYSTEM_LEAN') return 'Monitor';
    return status.isEmpty ? 'Monitor' : status;
  }

  String _actionReason() {
    if (!prop.recommendationAvailable &&
        prop.recommendationUnavailableReason.trim().isNotEmpty) {
      return prop.recommendationUnavailableReason;
    }
    if (prop.opportunityReasons.isNotEmpty) {
      return prop.opportunityReasons.first;
    }
    return prop.recommendationExplanation.trim().isEmpty
        ? 'quality gates passed'
        : prop.recommendationExplanation;
  }

  @override
  Widget build(BuildContext context) {
    final side = prop.recommendedSide.trim().isEmpty
        ? 'N/A'
        : prop.recommendedSide;
    final confidenceLabel =
        '${prop.displayConfidenceLabel} (Tier: ${prop.tier.trim().isEmpty ? 'No Pick' : prop.tier})';
    final riskFlags =
        'Fallback ${_fallbackCount()}/3 | Freshness ${_lineupFreshness()} | Coverage ${_coverageSummary()}';
    final factors = [
      'Pitcher K% vs lineup K%: ${_pct(prop.pitcherKPercent)} vs ${_pct(prop.lineupKPercent)}',
      'Projected batters faced: ${prop.strikeoutProjectedBattersFaced?.toString() ?? '--'}',
      'Umpire boost: ${prop.umpireKBoost == null ? '--' : '${(prop.umpireKBoost! * 100).toStringAsFixed(1)}%'}',
      'Park factor: ${_num(prop.parkKFactor, decimals: 2)}',
    ];
    final action = _actionStatus();
    final actionColor = action == 'Actionable'
        ? const Color(0xFF8CFFB2)
        : action == 'Blocked'
        ? const Color(0xFFFF7B7B)
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
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 9),
          _row('Pick', '$side ${prop.line.toStringAsFixed(1)} ${prop.market}'),
          _row('Confidence', confidenceLabel),
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
