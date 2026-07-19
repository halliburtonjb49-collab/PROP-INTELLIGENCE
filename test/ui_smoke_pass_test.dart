import 'package:prop_intelligence/controllers/active_slip_controller.dart';
import 'package:prop_intelligence/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('smoke: scoreboard, analytics, line movement top navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const PropIntelligenceApp());
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('SCOREBOARD'), findsWidgets);
    expect(find.text('GAME MARKETS'), findsWidgets);
    expect(find.text('ANALYTICS'), findsOneWidget);
    expect(find.text('LINE MOVEMENT'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('GAME MARKETS').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('MONEYLINE'), findsOneWidget);
    expect(find.text('SPREADS'), findsOneWidget);
    expect(find.text('GAME TOTALS'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('SCOREBOARD').first);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('ALL GAMES'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('ANALYTICS'));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('LINE MOVEMENT'));
    await tester.tap(find.text('LINE MOVEMENT'));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  test('smoke: active slip startup and add/remove interactions', () async {
    final controller = ActiveSlipController();
    await controller.load();

    expect(controller.legCount, 0);
    expect(controller.isEmpty, true);

    final added = await controller.addLegs([
      {
        'prop_id': 'smoke-prop-1',
        'player': 'Smoke Test Player',
        'sport': 'MLB',
        'market': 'Hits',
        'line': 0.5,
        'side': 'OVER',
        'odds': -110,
      },
    ]);

    expect(added, 1);
    expect(controller.legCount, 1);

    await controller.removeLeg('smoke-prop-1');
    expect(controller.legCount, 0);
    expect(controller.isEmpty, true);
  });

  testWidgets('smoke: every primary workspace destination opens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const PropIntelligenceApp());
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('ELITE ACTIVE'), findsNothing);

    Future<void> openWorkspace(String label, String? expected) async {
      final destination = find.text(label);
      expect(destination, findsOneWidget);
      await tester.ensureVisible(destination);
      await tester.tap(destination);
      await tester.pump(const Duration(milliseconds: 1200));
      if (expected != null) {
        expect(find.text(expected), findsWidgets);
      }
      expect(tester.takeException(), isNull);
    }

    await tester.tap(find.byKey(const ValueKey('board-active-slip-button')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);

    await openWorkspace('THE LAB', 'INTELLIGENCE LAB');
    await openWorkspace('PROP BUILDER', 'PROP BUILDER');
    await openWorkspace('BUILD\nPERFORM', null);
    await openWorkspace('EV SCANNER', 'EV SCANNER');
  });
}
