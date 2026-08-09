import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/prop_data.dart';
import 'package:prop_intelligence/models/slip_selection.dart';
import 'package:prop_intelligence/services/api_service.dart';
import 'package:prop_intelligence/widgets/lock_slip_dialog.dart';

SlipSelection _selection(String id) {
  return SlipSelection(
    prop: PropData.fromJson({
      'id': id,
      'player': 'Player $id',
      'sport': 'NBA',
      'matchup': 'A @ B',
      'sportsbook': 'Prize Picks',
      'market': 'POINTS',
      'line': 20.5,
    }),
    side: PickSide.over,
  );
}

void main() {
  test('normalizes supported slip sites and preserves entry contracts', () {
    expect(normalizeSlipSite('Prize Picks'), 'PRIZEPICKS');
    expect(normalizeSlipSite('DraftKings Pick6'), 'PICK6');
    expect(normalizeSlipSite('FanDuel'), 'FANDUEL');
    expect(slipEntryTypesForSite('PRIZEPICKS'), ['POWER', 'FLEX']);
    expect(slipEntryTypesForSite('DRAFTKINGS'), ['PARLAY']);
  });

  test('fixed payout tables preserve supported leg boundaries', () {
    expect(
      fixedSlipMultiplier(site: 'PRIZEPICKS', entryType: 'POWER', legCount: 2),
      3,
    );
    expect(
      fixedSlipMultiplier(site: 'PRIZEPICKS', entryType: 'FLEX', legCount: 6),
      25,
    );
    expect(
      fixedSlipMultiplier(site: 'UNDERDOG', entryType: 'POWER', legCount: 6),
      40,
    );
    expect(
      fixedSlipMultiplier(site: 'PRIZEPICKS', entryType: 'FLEX', legCount: 2),
      1,
    );
  });

  testWidgets('two-leg PrizePicks slip previews payout and profit', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LockSlipDialog(
            selections: [_selection('one'), _selection('two')],
            apiService: ApiService(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(r'$30.00'), findsOneWidget);
    expect(find.text(r'$20.00'), findsOneWidget);
  });

  testWidgets('unsupported two-leg Flex play explains the limitation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LockSlipDialog(
            selections: [_selection('one'), _selection('two')],
            apiService: ApiService(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('FLEX PLAY'));
    await tester.pump();

    expect(
      find.text('Selected play type is not available for 2 legs.'),
      findsOneWidget,
    );
  });
}
