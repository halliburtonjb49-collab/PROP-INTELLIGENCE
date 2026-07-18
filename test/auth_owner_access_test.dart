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

  test('change request preserves approval lifecycle fields', () {
    final request = AppChangeRequest.fromJson({
      'id': 42,
      'requester_email': 'admin@example.com',
      'title': 'Update analytics filters',
      'description': 'Add the requested date and sport filters.',
      'status': 'approved',
      'owner_response': 'Approved for the next release.',
      'created_at': '2026-07-18T12:00:00Z',
      'reviewed_at': '2026-07-18T13:00:00Z',
    });

    expect(request.id, 42);
    expect(request.requesterEmail, 'admin@example.com');
    expect(request.isPending, isFalse);
    expect(request.ownerResponse, 'Approved for the next release.');
  });
}
