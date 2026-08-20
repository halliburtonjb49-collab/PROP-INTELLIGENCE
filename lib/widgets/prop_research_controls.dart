import 'package:flutter/material.dart';

import '../models/prop_data.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class ResearchToggle extends StatelessWidget {
  const ResearchToggle({super.key, required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // It was two small gold words with a chevron, which reads as a caption
    // rather than something to press: people did not know the evidence was
    // there, or that they could put it away again once they had read it.
    // A bordered control that says what it will do, and spans the card so
    // it is obvious and easy to hit.
    return Semantics(
      button: true,
      expanded: open,
      label: open ? 'Close research' : 'Open research',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PiDesign.controlRadius),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(
            minHeight: PiDesign.minimumTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: open ? .16 : .08),
            borderRadius: BorderRadius.circular(PiDesign.controlRadius),
            border: Border.all(
              color: AppColors.gold.withValues(alpha: open ? .9 : .55),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                open ? Icons.unfold_less_rounded : Icons.science_outlined,
                color: AppColors.gold,
                size: 13,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  open ? 'CLOSE RESEARCH' : 'VIEW RESEARCH',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 11,
                    letterSpacing: .7,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                open
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: AppColors.gold,
                size: 15,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PiVerdictBlock extends StatelessWidget {
  const PiVerdictBlock({
    super.key,
    required this.verdict,
    this.compactSummary = false,
  });

  final PropVerdict verdict;
  final bool compactSummary;

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
    final compact = MediaQuery.sizeOf(context).width < 600;
    final facts = <String>[
      if (verdict.maximumPlayableLine != null)
        'playable to ${verdict.maximumPlayableLine!.toStringAsFixed(1)}',
      if (verdict.betterPriceAt.isNotEmpty)
        'better at ${verdict.betterPriceAt}',
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compactSummary
            ? 7
            : compact
            ? 8
            : 10,
      ),
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
              if (!compactSummary)
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
          SizedBox(height: compactSummary ? 3 : 5),
          Text(
            verdict.reason,
            maxLines: compactSummary
                ? 2
                : compact
                ? 3
                : null,
            overflow: compactSummary || compact
                ? TextOverflow.ellipsis
                : TextOverflow.visible,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              height: 1.35,
            ),
          ),
          if (!compactSummary && facts.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              facts.join('  \u00b7  '),
              key: const ValueKey('pi-verdict-facts'),
              maxLines: compact ? 1 : null,
              overflow: compact ? TextOverflow.ellipsis : TextOverflow.visible,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (!compactSummary && verdict.recheck.isNotEmpty) ...[
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
