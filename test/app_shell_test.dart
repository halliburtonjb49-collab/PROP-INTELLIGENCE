import 'package:flutter/foundation.dart';
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
    ValueListenable<int>? currentViewCountListenable,
    VoidCallback? onMobileWatchSlip,
    ValueChanged<int>? onMobileNavigateIndex,
  }) {
    return MaterialApp(
      home: AppShell(
        leftSidebar: const Center(child: Text('WORKSPACE NAVIGATION')),
        topNavigation: const Center(child: Text('COMMAND BAR')),
        content: const Center(child: Text('PRIMARY WORKSPACE')),
        accountPanel: const Center(child: Text('ACCOUNT PANEL')),
        activeSlipPanel: const Center(child: Text('ACTIVE SLIP PANEL')),
        activeSlipCount: activeSlipCount,
        currentViewCountListenable: currentViewCountListenable,
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
    final currentViewCount = ValueNotifier<int>(42);
    addTearDown(currentViewCount.dispose);

    await tester.pumpWidget(
      buildShell(
        activeSlipCount: 1,
        currentViewCountListenable: currentViewCount,
      ),
    );

    expect(find.text('WORKSPACE NAVIGATION'), findsOneWidget);
    expect(find.text('COMMAND BAR'), findsOneWidget);
    expect(find.text('PRIMARY WORKSPACE'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('right-panel-current-view')),
      findsOneWidget,
    );
    expect(find.text('42'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('right-panel-account-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('right-panel-active-slip-button')),
      findsOneWidget,
    );
    expect(find.text('ACCOUNT PANEL'), findsNothing);
    expect(find.text('ACTIVE SLIP PANEL'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared shell meets labeled desktop touch-target guidelines', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildShell(activeSlipCount: 2));

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });

  testWidgets('desktop rail account button opens account panel', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildShell(activeSlipCount: 1));

    await tester.tap(find.byKey(const ValueKey('right-panel-account-button')));
    await tester.pumpAndSettle();

    expect(find.text('ACCOUNT PANEL'), findsOneWidget);
    expect(find.text('ACTIVE SLIP PANEL'), findsNothing);
  });

  testWidgets('desktop rail active slip button opens active slip panel', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildShell(activeSlipCount: 1));

    await tester.tap(
      find.byKey(const ValueKey('right-panel-active-slip-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('ACTIVE SLIP PANEL'), findsOneWidget);
    expect(find.text('ACCOUNT PANEL'), findsNothing);
  });

  testWidgets('desktop rail close button collapses panel', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildShell(activeSlipCount: 1));

    await tester.tap(
      find.byKey(const ValueKey('right-panel-active-slip-button')),
    );
    await tester.pump();

    expect(find.text('ACTIVE SLIP PANEL'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('right-panel-close')));
    await tester.pumpAndSettle();

    expect(find.text('ACTIVE SLIP PANEL'), findsNothing);
    expect(find.text('ACCOUNT PANEL'), findsNothing);
  });

  testWidgets('desktop right panel controls expose accessibility labels', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildShell(activeSlipCount: 2));

    expect(find.bySemanticsLabel('Open account'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Open active slip')), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('2 selected props in active slip')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('right-panel-active-slip-button')),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Close panel'), findsOneWidget);
  });

  testWidgets('desktop right rail controls are touch-accessible', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildShell(activeSlipCount: 2));

    expect(
      tester
          .getSize(find.byKey(const ValueKey('right-panel-account-button')))
          .height,
      greaterThanOrEqualTo(44.0),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('right-panel-active-slip-button')))
          .height,
      greaterThanOrEqualTo(44.0),
    );
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
    expect(find.text('ACTIVE SLIP PANEL'), findsOneWidget);
    expect(find.text('ACCOUNT PANEL'), findsNothing);
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

  testWidgets('active slip badge uses count and pulses once on increment', (
    tester,
  ) async {
    const accent = Color(0xFFC0C7D1);
    await tester.pumpWidget(
      const MaterialApp(home: ActiveSlipBadge(count: 0, accentColor: accent)),
    );

    final getScale = () => tester
        .widget<ScaleTransition>(
          find.byKey(const ValueKey('active-slip-badge-scale')),
        )
        .scale
        .value;
    expect(getScale(), equals(1.0));

    await tester.pumpWidget(
      const MaterialApp(home: ActiveSlipBadge(count: 1, accentColor: accent)),
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(getScale(), greaterThan(1.0));
    await tester.pump(const Duration(milliseconds: 500));
    expect(getScale(), closeTo(1.0, 0.001));

    await tester.pumpWidget(
      const MaterialApp(home: ActiveSlipBadge(count: 2, accentColor: accent)),
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(getScale(), greaterThan(1.0));
    await tester.pump(const Duration(milliseconds: 500));
    expect(getScale(), closeTo(1.0, 0.001));

    await tester.pump(const Duration(milliseconds: 1000));
    expect(getScale(), closeTo(1.0, 0.001));

    await tester.pumpWidget(
      const MaterialApp(home: ActiveSlipBadge(count: 1, accentColor: accent)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(getScale(), closeTo(1.0, 0.001));
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

  testWidgets('badge is readable and mobile shell still opens overlay', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(820, 1180));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildShell(activeSlipCount: 2));

    expect(find.text('2'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('mobile-nav-ticket')));
    await tester.pumpAndSettle();
    expect(find.text('ACTIVE SLIP PANEL'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('right-panel-close')));
    await tester.pumpAndSettle();
    expect(find.text('ACTIVE SLIP PANEL'), findsNothing);
  });
}
