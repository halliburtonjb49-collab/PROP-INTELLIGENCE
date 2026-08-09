import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class ActiveBoardFilters extends StatelessWidget {
  const ActiveBoardFilters({
    super.key,
    required this.labels,
    required this.onClearAll,
  });

  final List<String> labels;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();
    return Semantics(
      container: true,
      label: 'Active prop filters: ${labels.join(', ')}',
      child: Container(
        key: const ValueKey('active-board-filters'),
        height: 36,
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF07111C),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.filter_alt_rounded,
              size: 14,
              color: AppColors.gold,
            ),
            const SizedBox(width: 6),
            const Text(
              'FILTERED BY',
              style: TextStyle(
                color: AppColors.gold,
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: .5,
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: labels.length,
                separatorBuilder: (_, _) => const SizedBox(width: 5),
                itemBuilder: (_, index) => Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: AppColors.gold.withValues(alpha: .45),
                      ),
                    ),
                    child: Text(
                      labels[index],
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            TextButton(
              key: const ValueKey('clear-board-filters'),
              onPressed: onClearAll,
              child: const Text(
                'CLEAR',
                style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
