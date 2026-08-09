import 'package:flutter/material.dart';

import '../models/prop_data.dart';
import '../theme/app_colors.dart';

class InjuryImpactSummary {
  const InjuryImpactSummary({
    required this.level,
    required this.title,
    required this.details,
  });

  final String level;
  final String title;
  final List<String> details;

  bool get isPresent => details.isNotEmpty;
}

InjuryImpactSummary buildInjuryImpactSummary(PropData prop) {
  final injury = prop.injuryStatus.trim().toLowerCase().replaceAll('_', ' ');
  final lineup = prop.lineupStatus.trim().toLowerCase().replaceAll('_', ' ');
  final details = <String>[];
  var level = 'WATCH';
  if ({'out', 'inactive', 'injured reserve', 'suspended'}.contains(injury)) {
    level = 'CRITICAL';
    details.add(
      '${prop.player} is listed $injury; this prop should not be treated as playable.',
    );
  } else if ({
    'doubtful',
    'questionable',
    'day to day',
    'day-to-day',
    'game time decision',
    'probable',
  }.contains(injury)) {
    level = injury == 'doubtful' ? 'HIGH' : 'WATCH';
    details.add(
      '${prop.player} is listed $injury; recheck availability before research is finalized.',
    );
  }

  const unavailableLineups = {'out', 'inactive'};
  const unreportedLineups = {
    '',
    'unknown',
    'unavailable',
    'no report',
    'not reported',
  };
  if (unavailableLineups.contains(lineup)) {
    level = 'CRITICAL';
    details.add(
      '${prop.player} has lineup status $lineup; this prop should not be treated as playable.',
    );
  } else if (!unreportedLineups.contains(lineup) &&
      !{
        'confirmed',
        'confirmed starter',
        'starter',
        'starting',
        'active',
      }.contains(lineup)) {
    if ({
      'doubtful',
      'bench',
      'limited',
      'minutes restriction',
    }.contains(lineup)) {
      level = 'HIGH';
    }
    details.add(
      'Lineup status is $lineup; role and opportunity can still change.',
    );
  }
  if (prop.roleChange.trim().isNotEmpty &&
      prop.roleChange.toUpperCase() != 'UNKNOWN' &&
      prop.roleChange.toUpperCase() != 'STABLE') {
    details.add(
      'Verified role trend: ${prop.roleChange.replaceAll('_', ' ').toLowerCase()}.',
    );
  }
  void addFactor(String label, double? value) {
    if (value == null || (value - 1).abs() < .02) return;
    final change = (value - 1) * 100;
    details.add(
      '$label context ${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}%.',
    );
  }

  addFactor('Usage', prop.usageMultiplier);
  addFactor('With/without teammate', prop.wowyMultiplier);
  addFactor('Opportunity', prop.opportunityMultiplier);
  return InjuryImpactSummary(
    level: level,
    title: level == 'CRITICAL'
        ? 'AVAILABILITY BLOCK'
        : 'INJURY / LINEUP IMPACT',
    details: details,
  );
}

class InjuryImpactAlert extends StatelessWidget {
  const InjuryImpactAlert({super.key, required this.prop});

  final PropData prop;

  @override
  Widget build(BuildContext context) {
    final summary = buildInjuryImpactSummary(prop);
    if (!summary.isPresent) return const SizedBox.shrink();
    final critical = summary.level == 'CRITICAL' || summary.level == 'HIGH';
    final color = critical ? const Color(0xFFFF806B) : AppColors.gold;
    return Container(
      key: const ValueKey('injury-impact-alert'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.health_and_safety_outlined, color: color, size: 16),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  summary.title,
                  style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                summary.level,
                style: TextStyle(
                  color: color,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final detail in summary.details.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '• $detail',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 9,
                  height: 1.25,
                ),
              ),
            ),
          const Text(
            'Only verified status and model context factors are shown; PI does not invent an injury projection delta.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 8,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}
