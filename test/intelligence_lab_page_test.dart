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
    expect(find.text('GAME-SCRIPT SIMULATOR'), findsOneWidget);
    expect(find.text('RUN INTELLIGENCE'), findsOneWidget);
    expect(find.text('QUICK GUIDE'), findsOneWidget);
    expect(find.byIcon(Icons.help_outline_rounded), findsAtLeastNWidgets(3));

    await tester.tap(find.text('QUICK GUIDE'));
    await tester.pumpAndSettle();
    expect(find.text('How to use Intelligence Lab'), findsOneWidget);
    expect(find.text('START ANALYSIS'), findsOneWidget);
  });

  testWidgets('Intelligence Lab starts from active slip selections', (
    tester,
  ) async {
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
      find.widgetWithText(TextField, 'Active Slip Player'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, 'Assists'), findsOneWidget);
    expect(find.widgetWithText(TextField, '8.2'), findsOneWidget);
    expect(find.widgetWithText(TextField, '7.5'), findsOneWidget);
  });
}
