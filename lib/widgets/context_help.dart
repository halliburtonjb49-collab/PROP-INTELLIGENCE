import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class ContextHelp extends StatelessWidget {
  const ContextHelp({super.key, required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Learn about $title',
      child: IconButton(
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        color: AppColors.textSecondary,
        onPressed: () => showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.panel,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppColors.borderGold),
            ),
            title: Row(
              children: [
                const Icon(
                  Icons.lightbulb_outline_rounded,
                  color: AppColors.gold,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(title)),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Text(
                message,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.55,
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('GOT IT'),
              ),
            ],
          ),
        ),
        icon: const Icon(Icons.help_outline_rounded),
      ),
    );
  }
}

class GuidedSectionHeader extends StatelessWidget {
  const GuidedSectionHeader({
    super.key,
    required this.step,
    required this.title,
    required this.description,
    required this.help,
  });

  final int step;
  final String title;
  final String description;
  final String help;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderGold),
          ),
          child: Text(
            '$step',
            style: const TextStyle(
              color: AppColors.gold,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .35,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        ContextHelp(title: title, message: help),
      ],
    );
  }
}
