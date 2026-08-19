import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/controllers/active_slip_controller.dart';
import 'package:prop_intelligence/models/saved_slip.dart';
import 'package:prop_intelligence/widgets/slip_history_panel.dart';

void main() {
  test('final graded ticket resolves out of the active watcher', () {
    const slip = SavedSlip(
      id: 'final-slip',
      status: 'active',
      stake: 10,
      potentialPayout: 30,
      createdAt: null,
      legs: [
        SavedSlipLeg(
          propId: 'won-leg',
          eventId: 'event-1',
          player: 'Winner',
          sport: 'MLB',
          matchup: 'Away @ Home',
          sportsbook: 'PrizePicks',
          market: 'Hits',
          line: 1.5,
          entryLine: 1.5,
          side: 'OVER',
        ),
        SavedSlipLeg(
          propId: 'lost-leg',
          eventId: 'event-1',
          player: 'Loser',
          sport: 'MLB',
          matchup: 'Away @ Home',
          sportsbook: 'PrizePicks',
          market: 'Strikeouts',
          line: 4.5,
          entryLine: 4.5,
          side: 'UNDER',
        ),
      ],
    );

    expect(
      terminalSlipStatus(slip, const {
        'won-leg': {
          'game_status': 'Final',
          'result_status': 'win',
          'result_value': 2,
        },
        'lost-leg': {
          'game_status': 'Final',
          'result_status': 'loss',
          'result_value': 7,
        },
      }),
      'lost',
    );
  });

  test('in-progress ticket stays in the active watcher', () {
    const slip = SavedSlip(
      id: 'live-slip',
      status: 'active',
      stake: 10,
      potentialPayout: 30,
      createdAt: null,
      legs: [
        SavedSlipLeg(
          propId: 'live-leg',
          eventId: 'event-1',
          player: 'Live Player',
          sport: 'MLB',
          matchup: 'Away @ Home',
          sportsbook: 'PrizePicks',
          market: 'Hits',
          line: 1.5,
          entryLine: 1.5,
          side: 'OVER',
        ),
      ],
    );

    expect(
      terminalSlipStatus(slip, const {
        'live-leg': {
          'game_status': 'Live',
          'result_status': 'win',
          'result_value': 2,
        },
      }),
      isNull,
    );
  });

  testWidgets('Slip Watcher close button exits through its route callback', (
    tester,
  ) async {
    final controller = ActiveSlipController();
    var closed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SlipHistoryPanel(
            activeSlipController: controller,
            onClose: () => closed = true,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('close-slip-watcher')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('close-slip-watcher')));
    expect(closed, isTrue);
  });

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
            projection: 1.92,
            confidence: 64,
            projectionSource: 'verified model',
            projectionModelVersion: '2026.8',
            projectionCalibrated: true,
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
    expect(
      find.text('MODEL 1.92  •  CONF 64%  •  VERIFIED MODEL'),
      findsOneWidget,
    );
    expect(find.byType(LinearProgressIndicator), findsNWidgets(3));
    expect(find.text('PROFIT KEEPER'), findsNothing);
    expect(find.textContaining('UPDATING SLIP RESULTS'), findsNothing);

    await tester.tap(find.byIcon(Icons.insights_rounded));
    await tester.pump();
    expect(find.text('PROFIT KEEPER'), findsOneWidget);
  });
}
