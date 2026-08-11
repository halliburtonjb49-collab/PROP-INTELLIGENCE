import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/member_identity.dart';
import 'package:prop_intelligence/services/auth_manager.dart';
import 'package:prop_intelligence/widgets/member_identity_badge.dart';

void main() {
  test('owner grant raises access without replacing a higher paid tier', () {
    expect(
      highestSubscriptionTier(
        SubscriptionTier.free,
        grantedTierForRole('core'),
      ),
      SubscriptionTier.core,
    );
    expect(
      highestSubscriptionTier(
        SubscriptionTier.edge,
        grantedTierForRole('core'),
      ),
      SubscriptionTier.edge,
    );
  });

  test('Pro Founder identity takes precedence over paid tier branding', () {
    expect(
      MemberIdentityRole.fromValues(
        accountRole: 'user',
        assignedRole: 'pro_founder',
        subscriptionTier: SubscriptionTier.edge,
      ),
      MemberIdentityRole.proFounder,
    );
  });

  testWidgets('numbered founder badge opens member details', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MemberIdentityBadge(
            username: 'first_member',
            role: MemberIdentityRole.proFounder,
            founderNumber: 7,
          ),
        ),
      ),
    );

    expect(find.text('PRO FOUNDER #007'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('member-identity-first_member')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('member-identity-profile')),
      findsOneWidget,
    );
    expect(find.text('PRO FOUNDER #007'), findsNWidgets(2));
    expect(
      find.textContaining('complimentary full Pro access'),
      findsOneWidget,
    );
  });

  testWidgets('compact Owner badge uses the full official artwork', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MemberIdentityBadge(
            username: 'prop_owner',
            role: MemberIdentityRole.owner,
            compact: true,
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/branding/founder_roles/owner.png',
    );
  });

  test('complimentary Pro access does not require payment', () {
    const state = AuthSessionState(
      ready: true,
      authenticated: true,
      isPremium: false,
      subscriptionTier: SubscriptionTier.free,
      assignedMemberRole: 'pro_founder',
      founderNumber: 12,
      role: 'user',
      userId: 'founder-id',
      email: 'founder@example.com',
      message: 'Authenticated',
    );

    expect(state.requiresPaidPlan, isFalse);
    expect(state.hasCoreAccess, isTrue);
    expect(state.hasEdgeAccess, isTrue);
    expect(state.subscriptionTier, SubscriptionTier.free);
  });
}
