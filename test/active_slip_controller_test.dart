import 'dart:convert';

import 'package:prop_intelligence/controllers/active_slip_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prop_intelligence/models/saved_slip.dart';
import 'package:prop_intelligence/models/prop_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('adds unique props and skips duplicates', () async {
    final controller = ActiveSlipController();
    await controller.load();

    final firstAdd = await controller.addLegs([
      {'prop_id': 'prop-1', 'player': 'Player One', 'line': 15.5},
    ]);

    final duplicateAdd = await controller.addLegs([
      {'prop_id': 'prop-1', 'player': 'Player One', 'line': 15.5},
    ]);

    expect(firstAdd, 1);
    expect(duplicateAdd, 0);
    expect(controller.legCount, 1);
  });

  test('allows multiple props from the same normalized prop site', () async {
    final controller = ActiveSlipController();
    await controller.load();

    final added = await controller.addLegs([
      {
        'prop_id': 'prop-1',
        'prop_site': 'DraftKings Sportsbook',
        'player': 'Pitcher One',
      },
      {
        'prop_id': 'prop-2',
        'sportsbook': 'DRAFT KINGS',
        'player': 'Pitcher Two',
      },
    ]);

    expect(added, 2);
    expect(controller.legCount, 2);
  });

  test('blocks a prop from a different site', () async {
    final controller = ActiveSlipController();
    await controller.load();
    await controller.addLegs([
      {'prop_id': 'prop-1', 'prop_site': 'FanDuel'},
    ]);

    final added = await controller.addLegs([
      {'prop_id': 'prop-2', 'prop_site': 'PrizePicks'},
    ]);

    expect(added, 0);
    expect(controller.legCount, 1);
  });

  test('refreshes an active leg when its site line changes', () async {
    final controller = ActiveSlipController();
    await controller.load();
    await controller.addLegs([
      {
        'prop_id': 'strikeout-1',
        'prop_site': 'FanDuel',
        'line': 5.5,
        'current_line': 5.5,
        'side': 'OVER',
        'current_odds': -110,
      },
    ]);

    await controller.refreshFromProps([
      const PropData(
        id: 'strikeout-1',
        eventId: 'game-1',
        apiSportsGameId: '',
        playerId: 'pitcher-1',
        player: 'Pitcher One',
        sport: 'MLB',
        matchup: 'A @ B',
        sportsbook: 'FanDuel',
        market: 'Pitcher Strikeouts',
        line: 6.5,
        pick: 'OVER',
        edge: 4,
        imagePath: '',
        overOdds: -105,
        underOdds: -115,
      ),
    ]);

    expect(controller.legs.single['current_line'], 6.5);
    expect(controller.legs.single['line'], 5.5);
    expect(controller.legs.single['original_line'], 5.5);
    expect(controller.legs.single['current_odds'], -105);
    expect(controller.legs.single['movement_status'], 'UPDATED');
  });

  test(
    'matches a legacy line-based id by event player market and site',
    () async {
      final controller = ActiveSlipController();
      await controller.load();
      await controller.addLegs([
        {
          'prop_id': 'game-1-pitcher-one-pitcher-strikeouts-5-5-fanduel',
          'event_id': 'game-1',
          'player': 'Pitcher One',
          'market': 'Pitcher Strikeouts',
          'prop_site': 'FanDuel',
          'line': 5.5,
          'current_line': 5.5,
          'side': 'OVER',
        },
      ]);

      await controller.refreshFromProps([
        const PropData(
          id: 'game-1-pitcher-one-pitcher-strikeouts-fanduel',
          eventId: 'game-1',
          apiSportsGameId: '',
          playerId: 'pitcher-1',
          player: 'Pitcher One',
          sport: 'MLB',
          matchup: 'A @ B',
          sportsbook: 'FanDuel',
          market: 'Pitcher Strikeouts',
          line: 6.5,
          pick: 'OVER',
          edge: 4,
          imagePath: '',
        ),
      ]);

      expect(
        controller.legs.single['prop_id'],
        'game-1-pitcher-one-pitcher-strikeouts-fanduel',
      );
      expect(controller.legs.single['original_line'], 5.5);
      expect(controller.legs.single['current_line'], 6.5);
    },
  );

  test('removes a prop', () async {
    final controller = ActiveSlipController();
    await controller.load();
    await controller.addLegs([
      {'prop_id': 'prop-1', 'player': 'Player One', 'line': 15.5},
    ]);

    await controller.removeLeg('prop-1');
    expect(controller.isEmpty, true);
  });

  test('preserves ordered positions', () async {
    final controller = ActiveSlipController();
    await controller.load();

    await controller.addLegs([
      {'prop_id': 'prop-1'},
      {'prop_id': 'prop-2'},
    ]);

    await controller.reorder(0, 1);

    expect(controller.legs.first['prop_id'], 'prop-2');
    expect(controller.legs.last['prop_id'], 'prop-1');
  });

  test('loads persisted slips from storage', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'prop_intelligence_active_slip_v1',
      jsonEncode([
        {'prop_id': 'prop-1', 'player': 'Player One', 'line': 15.5},
      ]),
    );

    final controller = ActiveSlipController();
    await controller.load();

    expect(controller.legCount, 1);
    expect(controller.legs.first['prop_id'], 'prop-1');
    expect(controller.legs.first['player'], 'Player One');
  });

  test('optimistic locked slip is visible and replaceable immediately', () {
    final controller = ActiveSlipController();
    final pending = SavedSlip(
      id: 'pending-1',
      status: 'active',
      stake: 10,
      potentialPayout: 10,
      createdAt: DateTime.utc(2026, 7, 26),
      legs: const [],
    );
    final saved = SavedSlip(
      id: 'saved-1',
      status: 'active',
      stake: 10,
      potentialPayout: 30,
      createdAt: DateTime.utc(2026, 7, 26),
      legs: const [],
    );

    controller.addOptimisticLockedSlip(pending);
    expect(controller.recentLockedSlips.single.id, 'pending-1');
    expect(controller.lockedSlipCount, 1);

    controller.replaceOptimisticLockedSlip('pending-1', saved);
    expect(controller.recentLockedSlips.single.id, 'saved-1');
    expect(controller.lockedSlipCount, 1);
  });

  test('settled locked slip is pruned from the recent cache', () {
    final controller = ActiveSlipController();
    final slip = SavedSlip(
      id: 'saved-1',
      status: 'active',
      stake: 10,
      potentialPayout: 20,
      createdAt: DateTime.utc(2026, 7, 28),
      legs: const [],
    );
    controller.addOptimisticLockedSlip(slip);
    controller.reconcileActiveLockedSlips(const []);

    expect(controller.recentLockedSlips, isEmpty);
  });
}
