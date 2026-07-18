import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/layout/app_shell.dart';

void main() {
  Widget buildShell() {
    return const MaterialApp(
      home: AppShell(
        leftSidebar: Center(child: Text('WORKSPACE NAVIGATION')),
        topNavigation: Center(child: Text('COMMAND BAR')),
        content: Center(child: Text('PRIMARY WORKSPACE')),
        rightSidebar: Center(child: Text('ACCOUNT AND SLIP')),
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
}
