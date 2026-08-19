import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/prop_data.dart';
import 'package:prop_intelligence/models/slip_selection.dart';
import 'package:prop_intelligence/services/api_service.dart';
import 'package:prop_intelligence/services/pickem_payout_rules.dart';
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
    expect(normalizeSlipSite('Betr Picks'), 'BETR');
    expect(normalizeSlipSite('FanDuel Picks'), 'FANDUEL_PICKS');
    expect(normalizeSlipSite('FanDuel'), 'FANDUEL');
    expect(slipEntryTypesForSite('PRIZEPICKS'), ['POWER', 'FLEX']);
    expect(slipEntryTypesForSite('UNDERDOG'), ['STANDARD', 'FLEX']);
    expect(slipEntryTypesForSite('BETR'), ['PERFECT', 'FLEX']);
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
      fixedSlipMultiplier(site: 'PRIZEPICKS', entryType: 'POWER', legCount: 3),
      6,
    );
    expect(
      fixedSlipMultiplier(site: 'PRIZEPICKS', entryType: 'FLEX', legCount: 2),
      2,
    );
    expect(
      fixedSlipMultiplier(site: 'UNDERDOG', entryType: 'STANDARD', legCount: 6),
      35,
    );
    expect(
      fixedSlipMultiplier(site: 'UNDERDOG', entryType: 'FLEX', legCount: 8),
      80,
    );
    expect(
      fixedSlipMultiplier(site: 'BETR', entryType: 'PERFECT', legCount: 8),
      100,
    );
    expect(
      fixedSlipMultiplier(site: 'BETR', entryType: 'FLEX', legCount: 10),
      200,
    );
  });

  test('flex payout tables include every winning result tier', () {
    expect(
      basePickemPayoutOutcomes(
        site: 'PRIZEPICKS',
        entryType: 'FLEX',
        legCount: 6,
      ),
      {6: 25, 5: 2, 4: 0.4},
    );
    expect(
      basePickemPayoutOutcomes(
        site: 'UNDERDOG',
        entryType: 'FLEX',
        legCount: 8,
      ),
      {8: 80, 7: 3, 6: 1},
    );
    expect(
      basePickemPayoutOutcomes(site: 'BETR', entryType: 'FLEX', legCount: 10),
      {10: 200, 9: 2, 8: 1.5, 7: 1.25, 6: 1},
    );
    expect(
      basePickemPayoutOutcomes(
        site: 'PICK6',
        entryType: 'CONTEST',
        legCount: 4,
      ),
      isEmpty,
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

  testWidgets('two-leg PrizePicks Flex shows current payout tiers', (
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

    expect(find.text(r'$20.00'), findsOneWidget);
    expect(find.text(r'$10.00'), findsOneWidget);
    expect(find.textContaining('2/2 correct: 2x'), findsOneWidget);
    expect(find.textContaining('1/2 correct: 0.5x'), findsOneWidget);
  });
}
