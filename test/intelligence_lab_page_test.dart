import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/pages/intelligence_lab_page.dart';
import 'package:prop_intelligence/models/prop_data.dart';
import 'package:prop_intelligence/models/slip_selection.dart';

void main() {
  testWidgets('Intelligence Lab exposes integrated workflows', (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: IntelligenceLabPage())),
    );

    expect(find.text('INTELLIGENCE LAB'), findsOneWidget);
    expect(find.text('PROP CORRELATION WORKFLOW'), findsOneWidget);
    expect(find.text('QUICK GUIDE'), findsOneWidget);
    await tester.tap(find.text('QUICK GUIDE'));
    await tester.pumpAndSettle();
    expect(find.text('How to use Intelligence Lab'), findsOneWidget);
    expect(find.text('START ANALYSIS'), findsOneWidget);
    await tester.tap(find.text('START ANALYSIS'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('GAME-SCRIPT SIMULATOR'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('GAME-SCRIPT SIMULATOR'), findsOneWidget);
    expect(find.text('RUN INTELLIGENCE'), findsOneWidget);
    expect(find.textContaining('REGRESSION TO MARKET'), findsOneWidget);
    expect(find.textContaining('PACE ADJUSTMENT'), findsOneWidget);
    expect(find.byIcon(Icons.help_outline_rounded), findsAtLeastNWidgets(2));

    expect(find.byKey(const ValueKey('scenario-minutes')), findsOneWidget);
    expect(find.byKey(const ValueKey('scenario-usage')), findsOneWidget);
    expect(find.byKey(const ValueKey('scenario-weather')), findsOneWidget);
    expect(find.byKey(const ValueKey('scenario-lineup')), findsOneWidget);
    expect(find.byKey(const ValueKey('scenario-reset')), findsOneWidget);
    expect(find.textContaining('user-controlled assumptions'), findsOneWidget);

  });

  testWidgets('Intelligence Lab starts from active slip selections', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const prop = PropData(
      id: 'prop-1',
      eventId: 'event-1',
      apiSportsGameId: '',
      playerId: 'player-1',
      player: 'Active Slip Player',
      sport: 'NBA',
      matchup: 'A vs B',
      sportsbook: 'FanDuel',
      market: 'Assists',
      projection: 8.2,
      line: 7.5,
      pick: 'OVER',
      edge: 5,
      imagePath: '',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: IntelligenceLabPage(
            selections: [SlipSelection(prop: prop, side: PickSide.under)],
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('lab-player-a')))
          .controller
          ?.text,
      'Active Slip Player',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('lab-market-a')))
          .controller
          ?.text,
      'Assists',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('lab-projection-a')))
          .controller
          ?.text,
      '8.2',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('lab-line-a')))
          .controller
          ?.text,
      '7.5',
    );
    expect(find.text('ACTIVE SLIP CONTEXT: NBA'), findsOneWidget);
  });
}
