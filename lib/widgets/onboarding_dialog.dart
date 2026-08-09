import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/engagement_tracker.dart';
import '../theme/app_colors.dart';

class ProductOnboarding {
  static const _preferenceKey = 'product_onboarding_v2_complete';

  static Future<void> showIfNeeded(BuildContext context) async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_preferenceKey) == true || !context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _OnboardingDialog(),
    );
    await preferences.setBool(_preferenceKey, true);
  }

  static Future<void> showDecisionGuide(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgBase,
      isScrollControlled: true,
      builder: (_) => const DecisionGuideSheet(),
    );
  }
}

class _OnboardingDialog extends StatefulWidget {
  const _OnboardingDialog();

  @override
  State<_OnboardingDialog> createState() => _OnboardingDialogState();
}

class _OnboardingDialogState extends State<_OnboardingDialog> {
  int page = 0;

  static const steps = <({IconData icon, String title, String body})>[
    (
      icon: Icons.travel_explore_rounded,
      title: 'Choose your board',
      body:
          'Start with a prop site, then choose a sport and market. Counts show the live inventory currently available for each filter.',
    ),
    (
      icon: Icons.fact_check_outlined,
      title: 'Read the PI verdict',
      body:
          'PLAY NOW means the current evidence supports action. SHOP means compare lines. LEAN is directional research. WAIT means the timing or evidence is not ready.',
    ),
    (
      icon: Icons.monitor_heart_outlined,
      title: 'Check data reliability',
      body:
          'The freshness strip shows when data was updated and what is available over the next three days. A gold warning means a provider feed may be incomplete.',
    ),
    (
      icon: Icons.query_stats_rounded,
      title: 'Understand the evidence',
      body:
          'Projection is the model estimate. Edge compares it with the current line. Confidence is an estimate, not a guarantee. Open a card to see the reasoning.',
    ),
    (
      icon: Icons.receipt_long_outlined,
      title: 'Build, track, and learn',
      body:
          'Add researched props to a slip, review correlation and line movement, then track the result. PROP INTELLIGENCE never places a wager for you.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final step = steps[page];
    final last = page == steps.length - 1;
    return AlertDialog(
      backgroundColor: AppColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.gunmetalLight),
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(step.icon, color: AppColors.gold, size: 44),
            const SizedBox(height: 18),
            Text(
              step.title.toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              step.body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.silver,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                steps.length,
                (index) => Container(
                  width: index == page ? 22 : 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: index == page
                        ? AppColors.gold
                        : AppColors.gunmetalLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            EngagementTracker.instance.recordProduct('ONBOARDING_SKIPPED');
            Navigator.pop(context);
          },
          child: const Text('SKIP'),
        ),
        if (page > 0)
          TextButton(
            onPressed: () => setState(() => page--),
            child: const Text('BACK'),
          ),
        FilledButton(
          onPressed: () {
            if (last) {
              EngagementTracker.instance.recordProduct('ONBOARDING_COMPLETE');
              Navigator.pop(context);
            } else {
              setState(() => page++);
            }
          },
          child: Text(last ? 'OPEN THE BOARD' : 'NEXT'),
        ),
      ],
    );
  }
}

class DecisionGuideSheet extends StatelessWidget {
  const DecisionGuideSheet({super.key});

  static const decisions = <({String name, String detail, Color color})>[
    (
      name: 'PLAY NOW',
      detail:
          'The current line, model evidence, and data quality support action now.',
      color: Color(0xFF55D6A3),
    ),
    (
      name: 'SHOP',
      detail:
          'The idea may be usable, but the current line is not the strongest available.',
      color: Color(0xFF78B7FF),
    ),
    (
      name: 'LEAN',
      detail:
          'The evidence suggests a direction, but it is not strong enough to call a model-backed play.',
      color: AppColors.gold,
    ),
    (
      name: 'WAIT',
      detail:
          'Lineup, freshness, price, or another important input is not ready.',
      color: Color(0xFFFFB35C),
    ),
    (
      name: 'PASS',
      detail: 'The available evidence does not support a directional decision.',
      color: AppColors.silver,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'HOW TO READ PI VERDICTS',
                    style: TextStyle(
                      color: Colors.white,
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
            ...decisions.map(
              (decision) => Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  border: Border.all(color: AppColors.gunmetalLight),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 76,
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      decoration: BoxDecoration(
                        color: decision.color.withValues(alpha: 0.16),
                        border: Border.all(color: decision.color),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        decision.name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: decision.color,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        decision.detail,
                        style: const TextStyle(
                          color: AppColors.silver,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Verdicts summarize research evidence. They are not guarantees or wagering instructions.',
              style: TextStyle(
                color: AppColors.silver,
                fontSize: 10,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
