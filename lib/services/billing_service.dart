import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_manager.dart';

enum PurchaseTier {
  core('core', 'core_tier'),
  edge('edge', 'edge_tier');

  const PurchaseTier(this.offeringId, this.entitlementId);
  final String offeringId;
  final String entitlementId;
}

class RevenueCatBillingService {
  RevenueCatBillingService({String? publicApiKey})
    : _publicApiKey =
          publicApiKey ??
          const String.fromEnvironment('REVENUECAT_PUBLIC_API_KEY');

  final SupabaseClient _supabase = Supabase.instance.client;
  final String _publicApiKey;

  Future<void> initializeBillingEngine() async {
    if (_publicApiKey.trim().isEmpty) {
      debugPrint('RevenueCat init skipped: missing REVENUECAT_PUBLIC_API_KEY.');
      return;
    }

    await Purchases.setLogLevel(LogLevel.debug);
    await Purchases.configure(PurchasesConfiguration(_publicApiKey));
    final userId = _supabase.auth.currentUser?.id;
    if (userId != null) {
      await Purchases.logIn(userId);
    }
  }

  Future<void> processPremiumSubscriptionPurchase(BuildContext context) async {
    return processSubscriptionPurchase(context, PurchaseTier.edge);
  }

  Future<void> processSubscriptionPurchase(
    BuildContext context,
    PurchaseTier tier,
  ) async {
    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.all[tier.offeringId];
      final package =
          current?.monthly ??
          (current != null && current.availablePackages.isNotEmpty
              ? current.availablePackages.first
              : null);

      if (package == null) {
        debugPrint('No RevenueCat package available for purchase.');
        return;
      }

      final customerInfo = await Purchases.purchasePackage(package);
      if (customerInfo.entitlements.all[tier.entitlementId]?.isActive == true) {
        await AuthManager.instance.refreshSessionState();

        if (context.mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Subscription active. Access will unlock after secure verification.',
              ),
              backgroundColor: Color(0xFF24C47E),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Transaction canceled or failed: $e');
    }
  }
}
