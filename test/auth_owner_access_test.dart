import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/services/auth_manager.dart';

void main() {
  test('verified owner email resolves to owner without metadata', () {
    expect(
      resolveAccountRole(email: 'HalliburtonJB49@Gmail.com ', role: 'user'),
      'owner',
    );
  });

  test('owner receives full Core and Edge access', () {
    const state = AuthSessionState(
      ready: true,
      authenticated: true,
      isPremium: true,
      subscriptionTier: SubscriptionTier.edge,
      role: 'owner',
      userId: 'owner-id',
      email: 'halliburtonjb49@gmail.com',
      message: 'Authenticated',
    );

    expect(state.isOwner, isTrue);
    expect(state.hasCoreAccess, isTrue);
    expect(state.hasEdgeAccess, isTrue);
  });
}
