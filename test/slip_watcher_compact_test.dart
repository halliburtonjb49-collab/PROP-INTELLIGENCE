import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/controllers/active_slip_controller.dart';
import 'package:prop_intelligence/models/saved_slip.dart';
import 'package:prop_intelligence/widgets/slip_history_panel.dart';

void main() {
  testWidgets('Slip Watcher opens directly to compact live prop cards', (
    tester,
  ) async {
    final controller = ActiveSlipController();
    controller.addOptimisticLockedSlip(
      SavedSlip(
        id: 'pending-test',
        status: 'active',
        stake: 10,
        potentialPayout: 10,
        createdAt: DateTime.utc(2026, 7, 26),
        legs: const [
          SavedSlipLeg(
            propId: 'prop-1',
            eventId: 'event-1',
            player: 'Test Player',
            sport: 'MLB',
            matchup: 'Away @ Home',
            sportsbook: 'PrizePicks',
            market: 'Hits',
            line: 1.5,
            entryLine: 1.5,
            side: 'OVER',
          ),
          SavedSlipLeg(
            propId: 'prop-2',
            eventId: 'event-1',
            player: 'Second Player',
            sport: 'MLB',
            matchup: 'Away @ Home',
            sportsbook: 'PrizePicks',
            market: 'Runs',
            line: 0.5,
            entryLine: 0.5,
            side: 'UNDER',
          ),
          SavedSlipLeg(
            propId: 'prop-3',
            eventId: 'event-1',
            player: 'Third Player',
            sport: 'MLB',
            matchup: 'Away @ Home',
            sportsbook: 'PrizePicks',
            market: 'RBIs',
            line: 1.5,
            entryLine: 1.5,
            side: 'OVER',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 700,
            child: SlipHistoryPanel(
              activeSlipController: controller,
              hasProAccess: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Test Player'), findsOneWidget);
    expect(find.text('Second Player'), findsOneWidget);
    expect(find.text('Third Player'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(3));
    expect(find.text('PROFIT KEEPER'), findsNothing);
    expect(find.textContaining('UPDATING SLIP RESULTS'), findsNothing);

    await tester.tap(find.byIcon(Icons.insights_rounded));
    await tester.pump();
    expect(find.text('PROFIT KEEPER'), findsOneWidget);
  });
}
