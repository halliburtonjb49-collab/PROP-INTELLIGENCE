import 'package:flutter/material.dart';

import '../screens/paywall_screen.dart';

class PremiumFeatureGateGuard extends StatelessWidget {
  final bool isUserPremium;
  final Widget child;
  final Widget? lockedChild;

  const PremiumFeatureGateGuard({
    super.key,
    required this.isUserPremium,
    required this.child,
    this.lockedChild,
  });

  void openPremiumPaywallSheetMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const BrandedPaywallModalSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isUserPremium) {
      return child;
    }

    final Widget lockedUi =
        lockedChild ??
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF131B24),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2E3B4D)),
          ),
          child: const Row(
            children: [
              Icon(Icons.lock_outline, color: Color(0xFFB7C3D0), size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Premium feature locked. Upgrade to unlock projections and edge details.',
                  style: TextStyle(color: Color(0xFFB7C3D0), fontSize: 12),
                ),
              ),
            ],
          ),
        );

    return InkWell(
      onTap: () => openPremiumPaywallSheetMenu(context),
      borderRadius: BorderRadius.circular(12),
      child: lockedUi,
    );
  }
}
