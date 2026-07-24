import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/services/auth_manager.dart';
import 'package:prop_intelligence/widgets/auth_account_panel.dart';

void main() {
  test('free users can discover the plan selector', () {
    expect(
      shouldShowPlanSelector(tier: SubscriptionTier.free, role: 'user'),
      isTrue,
    );
    expect(
      shouldShowSubscriptionManagement(
        tier: SubscriptionTier.free,
        role: 'user',
      ),
      isFalse,
    );
  });

  test('Core users can upgrade and manage their subscription', () {
    expect(
      shouldShowPlanSelector(tier: SubscriptionTier.core, role: 'user'),
      isTrue,
    );
    expect(
      shouldShowSubscriptionManagement(
        tier: SubscriptionTier.core,
        role: 'user',
      ),
      isTrue,
    );
  });

  test('Edge users manage their subscription without an upgrade prompt', () {
    expect(
      shouldShowPlanSelector(tier: SubscriptionTier.edge, role: 'user'),
      isFalse,
    );
    expect(
      shouldShowSubscriptionManagement(
        tier: SubscriptionTier.edge,
        role: 'user',
      ),
      isTrue,
    );
  });

  test(
    'privileged roles can preview plans without managing a fake purchase',
    () {
      for (final role in ['owner', 'admin', 'tester']) {
        expect(
          shouldShowPlanSelector(tier: SubscriptionTier.edge, role: role),
          isTrue,
        );
        expect(
          shouldShowSubscriptionManagement(
            tier: SubscriptionTier.edge,
            role: role,
          ),
          isFalse,
        );
      }
    },
  );
}
