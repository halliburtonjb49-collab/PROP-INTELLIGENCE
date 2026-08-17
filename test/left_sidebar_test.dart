import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/navigation/app_navigation.dart';
import 'package:prop_intelligence/services/auth_manager.dart';
import 'package:prop_intelligence/widgets/left_sidebar.dart';

void main() {
  testWidgets('sidebar forwards navigation, sport and refresh actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final count = ValueNotifier<int>(42);
    addTearDown(count.dispose);
    AppPage? selectedPage;
    String? selectedSport;
    var refreshes = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 250,
            child: LeftSidebar(
              selectedPage: AppPage.board,
              selectedSport: 'MLB',
              lockedSlipCount: 3,
              propCountListenable: count,
              onRefresh: () => refreshes++,
              onSelectPage: (value) => selectedPage = value,
              onSelectSport: (value) => selectedSport = value,
            ),
          ),
        ),
      ),
    );

    expect(find.text('42'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.byTooltip('Refresh props'));
    expect(refreshes, 1);
    await tester.tap(find.text('GAME MARKETS'));
    expect(selectedPage, AppPage.gameMarkets);
    await tester.tap(find.text('MLB'));
    expect(selectedSport, 'MLB');

    count.value = 57;
    await tester.pump();
    expect(find.text('57'), findsOneWidget);
  });

  testWidgets('sidebar fits a mobile viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final count = ValueNotifier<int>(8);
    addTearDown(count.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LeftSidebar(
            selectedPage: AppPage.board,
            selectedSport: 'ALL',
            lockedSlipCount: 0,
            propCountListenable: count,
            onRefresh: () {},
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('mobile-sidebar-prop-chat')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('operations center is visible only to the owner', (tester) async {
    final original = AuthManager.instance.sessionState.value;
    addTearDown(() => AuthManager.instance.sessionState.value = original);
    final count = ValueNotifier<int>(0);
    addTearDown(count.dispose);

    Future<void> renderForRole(String role) async {
      AuthManager.instance.sessionState.value = AuthSessionState(
        ready: true,
        authenticated: true,
        isPremium: true,
        subscriptionTier: SubscriptionTier.edge,
        role: role,
        userId: '$role-id',
        email: '$role@example.com',
        message: 'Authenticated',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 280,
              child: LeftSidebar(
                selectedPage: AppPage.board,
                selectedSport: 'ALL',
                lockedSlipCount: 0,
                propCountListenable: count,
                onRefresh: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    for (final role in ['user', 'core', 'pro', 'pro_founder', 'admin']) {
      await renderForRole(role);
      expect(
        find.byKey(const ValueKey('owner-operations-sidebar-button')),
        findsNothing,
        reason: '$role must not see Owner Ops',
      );
    }

    await renderForRole('owner');
    expect(AuthManager.instance.sessionState.value.isOwner, isTrue);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('owner-operations-sidebar-button')),
      500,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 20,
    );
    expect(
      find.byKey(const ValueKey('owner-operations-sidebar-button')),
      findsOneWidget,
    );
  });
}
