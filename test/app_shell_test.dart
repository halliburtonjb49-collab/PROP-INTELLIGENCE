import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/layout/app_shell.dart';

void main() {
  Widget buildShell({int activeSlipCount = 0}) {
    return MaterialApp(
      home: AppShell(
        leftSidebar: const Center(child: Text('WORKSPACE NAVIGATION')),
        topNavigation: const Center(child: Text('COMMAND BAR')),
        content: const Center(child: Text('PRIMARY WORKSPACE')),
        rightSidebar: const Center(child: Text('ACCOUNT AND SLIP')),
        activeSlipCount: activeSlipCount,
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
    await tester.tap(find.byTooltip('Open workspace navigation'));
    await tester.pumpAndSettle();
    expect(find.text('WORKSPACE NAVIGATION'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tapAt(const Offset(380, 420));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open account and active slip'));
    await tester.pumpAndSettle();
    expect(find.text('ACCOUNT AND SLIP'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile ticket icon shows active pick count', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildShell(activeSlipCount: 3));

    expect(
      find.byKey(const ValueKey('mobile-active-slip-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-active-slip-count')),
      findsOneWidget,
    );
    expect(find.text('3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet portrait uses touch-friendly drawer shell', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(820, 1180));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildShell(activeSlipCount: 2));

    expect(find.byTooltip('Open workspace navigation'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile-active-slip-count')),
      findsOneWidget,
    );
    expect(find.text('2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
