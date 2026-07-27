import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/layout/app_shell.dart';

void main() {
  Widget buildShell({
    int activeSlipCount = 0,
    int watchedSlipCount = 0,
    VoidCallback? onMobileWatchSlip,
    VoidCallback? onMobileChat,
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
        onMobileChat: onMobileChat,
      ),
    );
  }

  testWidgets('desktop shell presents all three premium workspace regions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildShell());

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
    expect(find.byKey(const ValueKey('mobile-nav-chat')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile-nav-active-slip')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mobile-nav-ticket')), findsOneWidget);
    expect(find.text('BOARD'), findsNothing);
    expect(find.text('GAMES'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile bottom navigation opens Slip Watcher', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var opened = false;

    await tester.pumpWidget(
      buildShell(watchedSlipCount: 3, onMobileWatchSlip: () => opened = true),
    );

    expect(find.text('SLIP WATCHER'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mobile-nav-active-slip')));
    expect(opened, isTrue);
    expect(find.text('3'), findsWidgets);
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
}
