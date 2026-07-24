import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'auth_manager.dart';
import 'supabase_service.dart';

enum PurchaseTier {
  core('core', 'core_tier'),
  edge('edge', 'edge_tier');

  const PurchaseTier(this.offeringId, this.entitlementId);
  final String offeringId;
  final String entitlementId;
}

@visibleForTesting
String subscriptionManagementUnavailableMessage({
  required bool hasActivePurchase,
}) => hasActivePurchase
    ? 'Subscription management is temporarily unavailable. Contact propsintell@gmail.com for cancellation or billing help.'
    : 'No active paid subscription was found for this account.';

@visibleForTesting
String selectRevenueCatPublicApiKey({
  required bool isWeb,
  required TargetPlatform platform,
  required String webKey,
  required String androidKey,
  required String iosKey,
  required String legacyKey,
}) {
  if (isWeb && webKey.trim().isNotEmpty) return webKey.trim();
  if (platform == TargetPlatform.android && androidKey.trim().isNotEmpty) {
    return androidKey.trim();
  }
  if (platform == TargetPlatform.iOS && iosKey.trim().isNotEmpty) {
    return iosKey.trim();
  }
  return legacyKey.trim();
}

class RevenueCatBillingService {
  RevenueCatBillingService({String? publicApiKey})
    : _publicApiKeyOverride = publicApiKey;

  final String? _publicApiKeyOverride;
  String get _publicApiKey =>
      _publicApiKeyOverride ??
      selectRevenueCatPublicApiKey(
        isWeb: kIsWeb,
        platform: defaultTargetPlatform,
        webKey: const String.fromEnvironment('REVENUECAT_WEB_PUBLIC_API_KEY'),
        androidKey: const String.fromEnvironment(
          'REVENUECAT_ANDROID_PUBLIC_API_KEY',
        ),
        iosKey: const String.fromEnvironment('REVENUECAT_IOS_PUBLIC_API_KEY'),
        legacyKey: const String.fromEnvironment('REVENUECAT_PUBLIC_API_KEY'),
      );
  static bool _configured = false;

  Future<void> initializeBillingEngine() async {
    if (_publicApiKey.trim().isEmpty) {
      throw StateError('Secure billing is not configured for this build.');
    }
    if (!_configured) {
      await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.warn);
      await Purchases.configure(PurchasesConfiguration(_publicApiKey));
      _configured = true;
    }
    final userId = SupabaseService.client?.auth.currentUser?.id;
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
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'This plan is temporarily unavailable. Please try again shortly.',
              ),
            ),
          );
        }
        return;
      }

      final purchaseResult = await Purchases.purchase(
        PurchaseParams.package(
          package,
          customerEmail: SupabaseService.client?.auth.currentUser?.email,
        ),
      );
      if (purchaseResult
              .customerInfo
              .entitlements
              .all[tier.entitlementId]
              ?.isActive ==
          true) {
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
              backgroundColor: Color(0xFF36B9FF),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Transaction canceled or failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Purchase was not completed. No subscription change was made.',
            ),
          ),
        );
      }
    }
  }

  Future<void> restorePurchases(BuildContext context) async {
    try {
      await initializeBillingEngine();
      await Purchases.restorePurchases();
      await AuthManager.instance.refreshSessionState();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Purchases restored. Your access has been refreshed.',
            ),
            backgroundColor: Color(0xFF36B9FF),
          ),
        );
      }
    } catch (error) {
      debugPrint('Purchase restore failed: $error');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to restore purchases right now.'),
          ),
        );
      }
    }
  }

  Future<void> openSubscriptionManagement(BuildContext context) async {
    try {
      await initializeBillingEngine();
      final customerInfo = await Purchases.getCustomerInfo();
      final managementUrl = customerInfo.managementURL?.trim();
      if (managementUrl == null || managementUrl.isEmpty) {
        final hasActivePurchase =
            customerInfo.activeSubscriptions.isNotEmpty ||
            customerInfo.entitlements.active.isNotEmpty;
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                subscriptionManagementUnavailableMessage(
                  hasActivePurchase: hasActivePurchase,
                ),
              ),
            ),
          );
        }
        return;
      }

      final launched = await launchUrl(
        Uri.parse(managementUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw StateError('Subscription portal could not be opened.');
      }
    } catch (error) {
      debugPrint('Subscription management failed: $error');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to open subscription management right now.'),
          ),
        );
      }
    }
  }
}
