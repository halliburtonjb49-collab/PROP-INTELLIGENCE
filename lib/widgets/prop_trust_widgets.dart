import 'package:flutter/material.dart';

import '../models/prop_data.dart';
import '../theme/app_colors.dart';

Color _trustColor(int score) {
  if (score >= 85) return const Color(0xFF55D6A3);
  if (score >= 70) return const Color(0xFF64B5F6);
  if (score >= 55) return AppColors.gold;
  return const Color(0xFFFF8A80);
}

class PiTrustBadge extends StatelessWidget {
  const PiTrustBadge({super.key, required this.prop});

  final PropData prop;

  @override
  Widget build(BuildContext context) {
    final score = prop.piTrustScore;
    final color = _trustColor(score);
    return Semantics(
      button: true,
      label: 'PI Trust Score $score out of 100, ${prop.piTrustBand}',
      child: InkWell(
        key: ValueKey('pi-trust-score-${prop.id}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: const Color(0xFF07111C),
          builder: (_) => PiTrustDetailsSheet(prop: prop),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: .75)),
          ),
          child: Row(
            children: [
              Icon(Icons.shield_outlined, color: color, size: 15),
              const SizedBox(width: 7),
              Text(
                'PI TRUST $score',
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .35,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  prop.piTrustResearchReady
                      ? '${prop.piTrustBand} | READY TO RESEARCH'
                      : '${prop.piTrustBand} | REVIEW WARNINGS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.silver,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PiTrustDetailsSheet extends StatelessWidget {
  const PiTrustDetailsSheet({super.key, required this.prop});

  final PropData prop;

  @override
  Widget build(BuildContext context) {
    final color = _trustColor(prop.piTrustScore);
    return SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 680),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
          shrinkWrap: true,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'PI TRUST SCORE ${prop.piTrustScore}/100',
                    style: TextStyle(
                      color: color,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const Text(
              'This measures data reliability, not whether the prop will win. '
              'A high score means the underlying line is dependable enough to research.',
              style: TextStyle(color: AppColors.silver, height: 1.4),
            ),
            const SizedBox(height: 16),
            for (final factor in prop.piTrustFactors) ...[
              _TrustFactorRow(factor: factor),
              const SizedBox(height: 8),
            ],
            if (prop.piTrustWarnings.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'CHECK BEFORE USING',
                style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              for (final warning in prop.piTrustWarnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 15,
                        color: AppColors.gold,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          warning,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TrustFactorRow extends StatelessWidget {
  const _TrustFactorRow({required this.factor});
  final Map<String, dynamic> factor;

  @override
  Widget build(BuildContext context) {
    final score = (factor['score'] as num?)?.toDouble() ?? 0;
    final maximum = (factor['maxScore'] as num?)?.toDouble() ?? 1;
    final ratio = maximum <= 0 ? 0.0 : (score / maximum).clamp(0.0, 1.0);
    final color = _trustColor((ratio * 100).round());
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.gunmetalLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  factor['label']?.toString() ?? 'Reliability factor',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${score.toStringAsFixed(score % 1 == 0 ? 0 : 1)}/${maximum.toStringAsFixed(0)}',
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          LinearProgressIndicator(
            value: ratio,
            minHeight: 5,
            borderRadius: BorderRadius.circular(99),
            color: color,
            backgroundColor: Colors.white10,
          ),
          const SizedBox(height: 6),
          Text(
            factor['detail']?.toString() ?? '',
            style: const TextStyle(color: AppColors.silver, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class WhyThisPropCapsule extends StatelessWidget {
  const WhyThisPropCapsule({super.key, required this.prop});

  final PropData prop;

  @override
  Widget build(BuildContext context) {
    final capsule = prop.researchCapsule;
    final items = (capsule['items'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    final summary = capsule['summary']?.toString().trim() ?? '';
    if (items.isEmpty && summary.isEmpty) return const SizedBox.shrink();

    return Container(
      key: ValueKey('why-this-prop-${prop.id}'),
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFF09131D),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.gunmetalLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.lightbulb_outline_rounded,
                color: AppColors.gold,
                size: 16,
              ),
              SizedBox(width: 7),
              Text(
                'WHY THIS PROP?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .4,
                ),
              ),
            ],
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              summary,
              style: const TextStyle(
                color: AppColors.silver,
                fontSize: 10,
                height: 1.35,
              ),
            ),
          ],
          if (items.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final item in items.take(7))
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      item['tone'] == 'CAUTION'
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_outline_rounded,
                      size: 14,
                      color: item['tone'] == 'CAUTION'
                          ? AppColors.gold
                          : const Color(0xFF55D6A3),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: const TextStyle(
                            color: AppColors.silver,
                            fontSize: 9.5,
                            height: 1.35,
                          ),
                          children: [
                            TextSpan(
                              text:
                                  '${item['label'] ?? 'Evidence'}: ${item['value'] ?? ''}. ',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            TextSpan(text: item['detail']?.toString() ?? ''),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
