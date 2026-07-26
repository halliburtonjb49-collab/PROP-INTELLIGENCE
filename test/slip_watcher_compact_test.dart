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
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('PROFIT KEEPER'), findsNothing);
    expect(find.textContaining('UPDATING SLIP RESULTS'), findsNothing);

    await tester.tap(find.byIcon(Icons.insights_rounded));
    await tester.pump();
    expect(find.text('PROFIT KEEPER'), findsOneWidget);
  });
}
