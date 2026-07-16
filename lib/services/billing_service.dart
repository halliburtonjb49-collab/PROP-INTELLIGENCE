import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_manager.dart';

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
  }

  Future<void> processPremiumSubscriptionPurchase(BuildContext context) async {
    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
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
      if (customerInfo.entitlements.all['elite_tier']?.isActive == true) {
        final upgraded = await _executeDatabasePremiumPromotion();
        await AuthManager.instance.refreshSessionState();

        if (upgraded && context.mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Subscription active. Premium unlocked.'),
              backgroundColor: Color(0xFF24C47E),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Transaction canceled or failed: $e');
    }
  }

  Future<bool> _executeDatabasePremiumPromotion() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      return false;
    }

    try {
      await _supabase
          .from('user_profiles')
          .update({'is_premium': true})
          .eq('id', user.id);
      debugPrint('Cloud verification updated. User promoted to ELITE.');
      return true;
    } catch (e) {
      debugPrint('Critical error patching database authorization records: $e');
      return false;
    }
  }
}
