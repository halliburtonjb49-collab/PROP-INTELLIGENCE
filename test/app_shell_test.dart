import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/layout/app_shell.dart';

void main() {
  test('mobile shell reclaims space without shrinking touch targets', () {
    expect(mobileShellInset(390), 5);
    expect(mobileShellGap(390), 5);
    expect(mobileTopBarHeight(320), 56);
    expect(mobileTopBarHeight(390), 58);
    expect(mobileTopBarHeight(768), 60);
    expect(mobileBottomBarHeight(320), 60);
    expect(mobileBottomBarHeight(390), 64);
    expect(mobileBottomBarHeight(768), 66);
  });
  Widget buildShell({
    int activeSlipCount = 0,
    int watchedSlipCount = 0,
    VoidCallback? onMobileWatchSlip,
    ValueChanged<int>? onMobileNavigateIndex,
  }) {
    return MaterialApp(
      home: AppShell(
        leftSidebar: const Center(child: Text('WORKSPACE NAVIGATION')),
        topNavigation: const Center(child: Text('COMMAND BAR')),
        content: const Center(child: Text('PRIMARY WORKSPACE')),
        rightSidebar: const Center(child: Text('ACCOUNT AND SLIP')),
        activeSlipCount: activeSlipCount,
        watchedSlipCount: watchedSlipCount,
        onMobileWatchSlip: onMobileWatchSlip,
        onMobileNavigateIndex: onMobileNavigateIndex,
      ),
    );
  }

  testWidgets('desktop shell presents all three premium workspace regions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildShell(activeSlipCount: 1));

    expect(find.text('WORKSPACE NAVIGATION'), findsOneWidget);
    expect(find.text('COMMAND BAR'), findsOneWidget);
    expect(find.text('PRIMARY WORKSPACE'), findsOneWidget);
    expect(find.text('ACCOUNT AND SLIP'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile shell exposes navigation and slip drawers', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildShell());

    expect(find.text('PRIMARY WORKSPACE'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mobile-nav-menu')));
    await tester.pumpAndSettle();
    expect(find.text('WORKSPACE NAVIGATION'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tapAt(const Offset(380, 420));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile-nav-ticket')));
    await tester.pumpAndSettle();
    expect(find.text('ACCOUNT AND SLIP'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile ticket icon shows active pick count', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildShell(activeSlipCount: 3));

    expect(find.byKey(const ValueKey('mobile-nav-ticket')), findsOneWidget);
    expect(find.text('3'), findsWidgets);
    expect(find.byKey(const ValueKey('mobile-nav-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-nav-board')), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-nav-games')), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-nav-watchlist')), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-nav-ticket')), findsOneWidget);
    expect(find.text('PROPS'), findsOneWidget);
    expect(find.text('GAMES'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile bottom navigation opens Slip Watcher', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var opened = false;

    await tester.pumpWidget(
      buildShell(watchedSlipCount: 3, onMobileWatchSlip: () => opened = true),
    );

    expect(find.text('WATCH'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mobile-nav-watchlist')));
    expect(opened, isTrue);
    expect(find.text('3'), findsWidgets);
  });

  testWidgets('mobile bottom navigation opens primary board destinations', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final destinations = <int>[];

    await tester.pumpWidget(
      buildShell(onMobileNavigateIndex: destinations.add),
    );

    await tester.tap(find.byKey(const ValueKey('mobile-nav-board')));
    await tester.tap(find.byKey(const ValueKey('mobile-nav-games')));
    expect(destinations, [0, 1]);
  });
  testWidgets('tablet portrait uses touch-friendly drawer shell', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(820, 1180));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildShell(activeSlipCount: 2));

    expect(find.byKey(const ValueKey('mobile-nav-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-nav-ticket')), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty slip still leaves a way to the account column', (
    tester,
  ) async {
    // Collapsing the empty column also hid the member's identity, their plan
    // controls and the only sign-out in the app, with no way back but
    // drafting a pick to earn the column again.
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: AppShell(
          leftSidebar: SizedBox(),
          topNavigation: SizedBox(),
          content: SizedBox(),
          rightSidebar: Text('ACCOUNT PANEL'),
          activeSlipCount: 0,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('ACCOUNT PANEL'), findsNothing);
    expect(find.byKey(const ValueKey('account-column-handle')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('account-column-handle')));
    await tester.pump();

    expect(find.text('ACCOUNT PANEL'), findsOneWidget);
  });
}
