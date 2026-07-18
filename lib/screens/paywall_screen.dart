import 'package:flutter/material.dart';

import '../services/billing_service.dart';

class BrandedPaywallModalSheet extends StatelessWidget {
  const BrandedPaywallModalSheet({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryYellow = Color(0xFFFFD700);
    final billingService = RevenueCatBillingService();

    return Container(
      padding: const EdgeInsets.all(32.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E222A),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          const Icon(Icons.bolt, color: primaryYellow, size: 54),
          const SizedBox(height: 12),
          const Text(
            'CHOOSE YOUR PROP INTELLIGENCE PLAN',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Research tools for every level of play',
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
          ),
          const Divider(color: Colors.white10, height: 40),
          _buildValueHookRow(
            Icons.dashboard_outlined,
            'Core includes the daily essentials',
            'Prop builder, player analytics, live scoreboard, and standard stat tracking.',
          ),
          _buildValueHookRow(
            Icons.analytics_outlined,
            'Python AI Projection Edge Metrics',
            'Access high-confidence historical simulation percentages.',
          ),
          _buildValueHookRow(
            Icons.notifications_active_outlined,
            'Real-Time Stale Line Movement Alerts',
            'Catch bookmakers before lines lock or slip shifts.',
          ),
          _buildValueHookRow(
            Icons.local_fire_department_outlined,
            'High-Multiplier Goblins Tier Alternative Lines',
            'Filter volatile alt-prop options automatically.',
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton(
              onPressed: () async {
                await billingService.initializeBillingEngine();
                if (context.mounted) {
                  await billingService.processSubscriptionPurchase(
                    context,
                    PurchaseTier.core,
                  );
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: primaryYellow),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'CHOOSE CORE - \$29.99 / MONTH',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () async {
                await billingService.initializeBillingEngine();
                if (context.mounted) {
                  await billingService.processSubscriptionPurchase(
                    context,
                    PurchaseTier.edge,
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryYellow,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'CHOOSE PRO / EDGE - \$89.99 / MONTH',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Cancel anytime. Managed securely via Apple App Store / Google Play billing pipelines.',
            style: TextStyle(color: Colors.grey[500], fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildValueHookRow(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFFFD700), size: 20),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
