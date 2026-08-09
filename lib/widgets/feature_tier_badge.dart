import 'package:flutter/material.dart';

import '../navigation/app_navigation.dart';
import '../services/auth_manager.dart';
import '../theme/app_colors.dart' as app_colors;

class FeatureTierBadge extends StatelessWidget {
  const FeatureTierBadge({
    super.key,
    required this.tier,
    this.compact = false,
    this.hasProUpgrade = false,
  });

  final SubscriptionTier tier;
  final bool compact;
  final bool hasProUpgrade;

  @override
  Widget build(BuildContext context) {
    final accountHasProAccess =
        AuthManager.instance.sessionState.value.hasEdgeAccess;
    final displayedTier = displayedTierForBadge(
      requiredTier: tier,
      hasEdgeAccess: accountHasProAccess,
      hasProUpgrade: hasProUpgrade,
    );
    final isCore = displayedTier == SubscriptionTier.core;
    final background = isCore
        ? app_colors.AppColors.silver
        : app_colors.AppColors.gold;
    const foreground = app_colors.AppColors.bgBase;

    return Container(
      key: ValueKey('tier-badge-${displayedTier.name}'),
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 7, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: isCore
            ? Border.all(color: const Color(0xFFF1F4F7), width: .7)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!compact) ...[
            Icon(Icons.workspace_premium, size: 12, color: foreground),
            const SizedBox(width: 5),
          ],
          Text(
            isCore ? 'CORE' : 'PRO',
            style: TextStyle(
              color: foreground,
              fontSize: compact ? 7 : 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
