import 'package:flutter/material.dart';

import '../services/slip_doctor_service.dart';
import '../theme/app_colors.dart' as app_colors;

class SlipDoctorPanel extends StatelessWidget {
  const SlipDoctorPanel({
    super.key,
    required this.legs,
    required this.onImprove,
    this.improving = false,
  });

  final List<Map<String, dynamic>> legs;
  final Future<void> Function() onImprove;
  final bool improving;

  @override
  Widget build(BuildContext context) {
    final report = SlipDoctorService.analyze(legs);
    final color = report.riskLevel == 'LOW'
        ? app_colors.AppColors.success
        : report.riskLevel == 'MODERATE'
        ? app_colors.AppColors.gold
        : app_colors.AppColors.danger;
    return Container(
      key: const ValueKey('smart-slip-doctor'),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.health_and_safety_outlined, color: color, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'SMART SLIP DOCTOR',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${report.score}/100 | ${report.riskLevel} RISK',
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (report.findings.isEmpty)
            const Text(
              'No same-player, contradiction, concentration, stale-line, or weak-data risks detected.',
              style: TextStyle(
                color: app_colors.AppColors.textSecondary,
                fontSize: 9,
                height: 1.3,
              ),
            )
          else
            for (final finding in report.findings.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      finding.severity == SlipRiskSeverity.high
                          ? Icons.error_outline_rounded
                          : Icons.warning_amber_rounded,
                      size: 14,
                      color: finding.severity == SlipRiskSeverity.high
                          ? app_colors.AppColors.danger
                          : app_colors.AppColors.gold,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: const TextStyle(
                            color: app_colors.AppColors.textSecondary,
                            fontSize: 9,
                            height: 1.25,
                          ),
                          children: [
                            TextSpan(
                              text: '${finding.title}: ',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            TextSpan(text: finding.detail),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          if (!report.healthy || report.riskLevel != 'LOW') ...[
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const ValueKey('improve-this-slip'),
                onPressed: improving ? null : onImprove,
                icon: improving
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_fix_high_rounded, size: 15),
                label: const Text('IMPROVE THIS SLIP'),
              ),
            ),
          ],
          const SizedBox(height: 3),
          const Text(
            'Doctor flags research risk only. It does not guarantee an outcome or place a wager.',
            style: TextStyle(
              color: app_colors.AppColors.textMuted,
              fontSize: 8,
            ),
          ),
        ],
      ),
    );
  }
}
