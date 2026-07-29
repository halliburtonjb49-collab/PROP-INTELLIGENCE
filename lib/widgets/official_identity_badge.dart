import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

bool isOfficialOwnerRole(String? role) => role?.trim().toLowerCase() == 'owner';

class OfficialOwnerBadge extends StatelessWidget {
  const OfficialOwnerBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Official PROP INTELLIGENCE owner',
      child: Container(
        key: const ValueKey('official-owner-badge'),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 5 : 7,
          vertical: compact ? 2 : 3,
        ),
        decoration: BoxDecoration(
          color: AppColors.gold.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.8)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.verified_rounded,
              size: compact ? 12 : 14,
              color: AppColors.gold,
            ),
            const SizedBox(width: 4),
            Text(
              'OFFICIAL OWNER',
              style: TextStyle(
                color: AppColors.gold,
                fontSize: compact ? 8 : 9,
                fontWeight: FontWeight.w900,
                letterSpacing: compact ? 0.25 : 0.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
