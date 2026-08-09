import 'package:flutter/material.dart';

import '../models/prop_data.dart';
import '../theme/app_colors.dart';

class ResearchToggle extends StatelessWidget {
  const ResearchToggle({super.key, required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              open ? 'HIDE RESEARCH' : 'SHOW RESEARCH',
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 9,
                letterSpacing: .6,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              open
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              color: AppColors.gold,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}

class PiVerdictBlock extends StatelessWidget {
  const PiVerdictBlock({super.key, required this.verdict});

  final PropVerdict verdict;

  ({Color accent, IconData icon}) get _treatment => switch (verdict.decision) {
    'PLAY_NOW' => (accent: AppColors.success, icon: Icons.bolt_rounded),
    'SHOP' => (
      accent: AppColors.goldHighlight,
      icon: Icons.travel_explore_rounded,
    ),
    'LEAN' => (accent: AppColors.gold, icon: Icons.trending_up_rounded),
    'WAIT' => (accent: AppColors.textSecondary, icon: Icons.schedule_rounded),
    _ => (
      accent: AppColors.textMuted,
      icon: Icons.remove_circle_outline_rounded,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final treatment = _treatment;
    final accent = treatment.accent;
    final facts = <String>[
      if (verdict.confidence > 0) '${verdict.confidence}% verdict confidence',
      if (verdict.maximumPlayableLine != null)
        'playable to ${verdict.maximumPlayableLine!.toStringAsFixed(1)}',
      if (verdict.betterPriceAt.isNotEmpty)
        'better at ${verdict.betterPriceAt}',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(9),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(treatment.icon, size: 15, color: accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  verdict.headline,
                  style: TextStyle(
                    color: accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
              const Text(
                'PI VERDICT',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 8,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            verdict.reason,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              height: 1.35,
            ),
          ),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              facts.join('  \u00b7  '),
              key: const ValueKey('pi-verdict-facts'),
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (verdict.recheck.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.refresh_rounded,
                  size: 11,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Recheck ${verdict.recheck.toLowerCase()}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
