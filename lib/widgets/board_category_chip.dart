import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class BoardCategoryChip extends StatelessWidget {
  const BoardCategoryChip({
    super.key,
    required this.category,
    required this.count,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  static const labelStyle = TextStyle(fontSize: 9, fontWeight: FontWeight.w900);

  final String category;
  final int count;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AppColors.gold : Colors.white;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Show $category, $count props',
      child: OutlinedButton.icon(
        key: ValueKey('category-filter-$category'),
        onPressed: onPressed,
        icon: Icon(icon, size: 14),
        label: Text(
          '$category $count',
          key: ValueKey('category-count-$category'),
          style: labelStyle,
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          backgroundColor: const Color(0xFF07111C),
          side: BorderSide(color: selected ? AppColors.gold : AppColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
      ),
    );
  }
}
