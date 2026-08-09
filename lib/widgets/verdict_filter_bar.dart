import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class VerdictFilterBar extends StatelessWidget {
  const VerdictFilterBar({
    super.key,
    required this.selected,
    required this.countFor,
    required this.onSelected,
    required this.onShowGuide,
    required this.shouldWrap,
  });

  final String selected;
  final int? Function(String value) countFor;
  final ValueChanged<String> onSelected;
  final VoidCallback onShowGuide;
  final bool Function(double width) shouldWrap;

  static const options = <(String, String)>[
    ('ALL', 'ALL PROPS'),
    ('ACTIONABLE', 'PLAYABLE'),
    ('PLAY_NOW', 'PLAY NOW'),
    ('SHOP', 'SHOP'),
    ('LEAN', 'LEAN'),
    ('WAIT', 'WAIT'),
  ];

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      for (final (value, label) in options) _chip(value, label),
      _guideButton(),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (shouldWrap(constraints.maxWidth)) {
          return Wrap(runSpacing: 7, children: chips);
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: chips),
        );
      },
    );
  }

  Widget _chip(String value, String label) {
    final count = countFor(value);
    final isSelected = selected == value;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: Semantics(
        button: true,
        selected: isSelected,
        label: count == null
            ? 'Show $label'
            : 'Show $label, $count available',
        child: GestureDetector(
          key: ValueKey('verdict-filter-$value'),
          onTap: () => onSelected(value),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.gold : const Color(0xFF07111C),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.gold),
            ),
            child: Text(
              count == null ? label : '$label $count',
              style: TextStyle(
                color: isSelected ? AppColors.bgBase : Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 9,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _guideButton() {
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: Semantics(
        button: true,
        label: 'Explain PI verdicts',
        child: GestureDetector(
          key: const ValueKey('verdict-guide-button'),
          onTap: onShowGuide,
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF07111C),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(
              Icons.question_mark_rounded,
              color: AppColors.gold,
              size: 15,
            ),
          ),
        ),
      ),
    );
  }
}
