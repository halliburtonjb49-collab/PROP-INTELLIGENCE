import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';

class ProductOnboarding {
  static const _preferenceKey = 'product_onboarding_v1_complete';

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
      icon: Icons.query_stats_rounded,
      title: 'Projection and edge',
      body:
          'Projection is the model’s expected result. Edge measures its estimated advantage relative to the current sportsbook line.',
    ),
    (
      icon: Icons.link_rounded,
      title: 'Correlation and context',
      body:
          'Use matchup, fatigue, officiating, and correlation signals together. No single metric should decide a play by itself.',
    ),
    (
      icon: Icons.science_outlined,
      title: 'Confidence and calibration',
      body:
          'Confidence is a model estimate—not a guarantee. Calibration remains clearly marked until 100 genuine pregame predictions are graded.',
    ),
    (
      icon: Icons.receipt_long_outlined,
      title: 'Build, track, and learn',
      body:
          'Compare the market, add researched props to your slip, and use graded history to improve your process over time.',
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
            Icon(
              step.icon,
              color: page == 2 ? AppColors.gold : AppColors.blue,
              size: 44,
            ),
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
        if (page > 0)
          TextButton(
            onPressed: () => setState(() => page--),
            child: const Text('BACK'),
          ),
        FilledButton(
          onPressed: () =>
              last ? Navigator.pop(context) : setState(() => page++),
          child: Text(last ? 'OPEN PROP INTELLIGENCE' : 'NEXT'),
        ),
      ],
    );
  }
}
