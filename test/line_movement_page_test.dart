import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/prop_data.dart';
import 'package:prop_intelligence/pages/line_movement_page.dart';

PropData _movementProp({
  required String id,
  required String player,
  required bool stale,
  required int ageSeconds,
  double opening = 6.5,
  double current = 8,
}) {
  final now = DateTime.now().toUtc();
  return PropData(
    id: id,
    eventId: 'event-1',
    apiSportsGameId: 'game-1',
    playerId: 'player-$id',
    player: player,
    sport: 'MLB',
    matchup: 'A @ B',
    sportsbook: 'PrizePicks',
    market: 'Hits + Runs + RBIs',
    lastUpdatedUtc: now
        .subtract(Duration(seconds: ageSeconds))
        .toIso8601String(),
    dataAgeSeconds: ageSeconds,
    dataStale: stale,
    recommendedSide: 'OVER',
    line: current,
    openingLine: opening,
    currentLine: current,
    lineMovedAtUtc: now.subtract(const Duration(minutes: 4)).toIso8601String(),
    pick: 'OVER',
    edge: 4,
    imagePath: '',
    marketOriginLine: 7.5,
    marketBookCount: 4,
  );
}

Future<List<PropData>> _fixtureLoader({
  required bool refresh,
  required String sport,
}) async {
  return [
    _movementProp(
      id: 'stale',
      player: 'Stale Player',
      stale: true,
      ageSeconds: 2400,
    ),
    _movementProp(
      id: 'fresh',
      player: 'Fresh Player',
      stale: false,
      ageSeconds: 90,
      opening: 10,
      current: 9,
    ),
  ];
}

void main() {
  testWidgets('shows freshness warnings and grounded provider comparison', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LineMovementPage(
            selectedSport: 'ALL',
            hasProAccess: true,
            loadProps: _fixtureLoader,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('line-freshness-warning')),
      findsOneWidget,
    );
    expect(find.textContaining('1 stale and 0 aging lines'), findsOneWidget);
    expect(find.text('STALE'), findsOneWidget);
    expect(find.text('FRESH'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('line-details-stale')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('line-movement-details')), findsOneWidget);
    expect(find.text('VERIFIED LINE TIMELINE'), findsOneWidget);
    expect(find.byKey(const ValueKey('provider-comparison')), findsOneWidget);
    expect(
      find.textContaining('Market median 7.5 across 4 providers'),
      findsOneWidget,
    );
    expect(
      find.textContaining('may no longer match the provider'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mobile card opens the same verified timeline without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LineMovementPage(
            selectedSport: 'MLB',
            hasProAccess: true,
            loadProps: _fixtureLoader,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final detailsButton = find.byKey(const ValueKey('line-details-fresh'));
    expect(detailsButton, findsOneWidget);
    await tester.ensureVisible(detailsButton);
    await tester.pumpAndSettle();
    await tester.tap(detailsButton);
    await tester.pumpAndSettle();

    expect(find.text('VERIFIED LINE TIMELINE'), findsOneWidget);
    expect(
      find.textContaining('Market median 7.5 across 4 providers'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
