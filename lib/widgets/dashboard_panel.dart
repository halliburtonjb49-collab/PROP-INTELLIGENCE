import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class DashboardPanel extends StatelessWidget {
  const DashboardPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderColor,
    this.radius = 12,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF081722), Color(0xFF06111B)],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: (borderColor ?? AppColors.border).withValues(alpha: .72),
        ),
      ),
      child: child,
    );
  }
}
