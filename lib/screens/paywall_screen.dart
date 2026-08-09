import 'package:flutter/material.dart';

import '../services/auth_manager.dart';
import '../services/billing_service.dart';
import '../services/subscription_pricing.dart';
import '../services/engagement_tracker.dart';

import '../theme/app_colors.dart' as brand_colors;

class SubscriptionRequiredScreen extends StatelessWidget {
  const SubscriptionRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050C13),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrandedPaywallModalSheet(
                    heading: 'CHOOSE A PLAN TO CONTINUE',
                    supportingText:
                        'PROP INTELLIGENCE is your all-in-one sports-prop command center for research, tracking, analytics, and community. Monthly plans start with 2 days free; annual plans start with 7 days free.',
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => AuthManager.instance.signOut(),
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('SIGN OUT'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BrandedPaywallModalSheet extends StatelessWidget {
  const BrandedPaywallModalSheet({
    super.key,
    this.heading = 'CHOOSE YOUR PROP INTELLIGENCE PLAN',
    this.supportingText =
        'Research, track, analyze, and discuss picks without placing bets in-app',
  });

  final String heading;
  final String supportingText;

  @override
  Widget build(BuildContext context) {
    EngagementTracker.instance.recordProductOncePer(
      'PAYWALL_VIEW',
      const Duration(seconds: 30),
    );
    const primaryYellow = brand_colors.AppColors.goldHighlight;
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
          Text(
            heading,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            supportingText,
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
            'Strikeout Pro Gold Multi-Site Research',
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
                'CHOOSE CORE - ${SubscriptionPricing.coreMonthly}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: () => billingService.processSubscriptionPurchase(
              context,
              PurchaseTier.core,
              interval: PurchaseInterval.annual,
            ),
            child: const Text(
              'CORE ANNUAL • ${SubscriptionPricing.coreAnnual} • 7-DAY FREE TRIAL',
            ),
          ),
          const SizedBox(height: 4),
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
                'CHOOSE PRO - ${SubscriptionPricing.proMonthly}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: () => billingService.processSubscriptionPurchase(
              context,
              PurchaseTier.edge,
              interval: PurchaseInterval.annual,
            ),
            child: const Text(
              'PRO ANNUAL • ${SubscriptionPricing.proAnnual} • 7-DAY FREE TRIAL',
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton(
              onPressed: () => billingService.processSubscriptionPurchase(
                context,
                PurchaseTier.foundingEdge,
              ),
              child: const Text(
                'FOUNDING PRO - ${SubscriptionPricing.foundingProMonthly}',
              ),
            ),
          ),
          TextButton(
            onPressed: () => billingService.processSubscriptionPurchase(
              context,
              PurchaseTier.foundingEdge,
              interval: PurchaseInterval.annual,
            ),
            child: const Text(
              'FOUNDING PRO ANNUAL • ${SubscriptionPricing.foundingProAnnual} • 7-DAY FREE TRIAL',
            ),
          ),
          const Text(
            'Monthly plans include a 2-day free trial. Founding Pro is limited to the first 100 members.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => billingService.restorePurchases(context),
            child: const Text('RESTORE PURCHASES'),
          ),
          Text(
            'Cancel anytime. Purchases and renewals are managed securely by the billing platform available on your device.',
            style: TextStyle(color: Colors.grey[500], fontSize: 10),
          ),
          const SizedBox(height: 6),
          Text(
            'Informational research only. Predictions are estimates, not guarantees. Use only where lawful and if you meet local age requirements.',
            textAlign: TextAlign.center,
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
          Icon(icon, color: brand_colors.AppColors.goldHighlight, size: 20),
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
