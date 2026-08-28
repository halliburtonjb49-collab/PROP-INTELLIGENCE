import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class PiFeatureHeader extends StatelessWidget {
  const PiFeatureHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.icon = Icons.auto_awesome_rounded,
    this.actions = const [],
    this.steps = const [],
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> actions;
  final List<String> steps;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF07141E),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.borderGold),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow.toUpperCase(),
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: .8,
              ),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Icon(icon, color: AppColors.gold, size: 23),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 18 : 21,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .45,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        );
        final workflow = steps.isEmpty
            ? const SizedBox.shrink()
            : Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  for (var index = 0; index < steps.length; index++)
                    PiWorkflowStep(
                      number: index + 1,
                      label: steps[index],
                      active: index == 0,
                    ),
                ],
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (compact) ...[
              copy,
              if (steps.isNotEmpty) const SizedBox(height: 14),
              workflow,
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: copy),
                  if (steps.isNotEmpty) const SizedBox(width: 20),
                  workflow,
                ],
              ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          ],
        );
      },
    ),
  );
}

class PiWorkflowStep extends StatelessWidget {
  const PiWorkflowStep({
    super.key,
    required this.number,
    required this.label,
    this.active = false,
  });

  final int number;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? AppColors.gold : Colors.transparent,
          border: Border.all(
            color: active ? AppColors.gold : AppColors.border,
          ),
        ),
        child: Text(
          '$number',
          style: TextStyle(
            color: active ? AppColors.background : AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      const SizedBox(width: 7),
      Text(
        label.toUpperCase(),
        style: TextStyle(
          color: active ? AppColors.gold : AppColors.textMuted,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: .35,
        ),
      ),
    ],
  );
}

class PiSectionLabel extends StatelessWidget {
  const PiSectionLabel({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: .55,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ),
      if (trailing != null) trailing!,
    ],
  );
}
