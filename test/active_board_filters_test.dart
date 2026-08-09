import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/widgets/active_board_filters.dart';

void main() {
  testWidgets('summarizes active filters and clears them', (tester) async {
    var cleared = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActiveBoardFilters(
            labels: const ['PRIZEPICKS', 'WNBA', 'REBOUNDS', 'PLAYABLE'],
            onClearAll: () => cleared = true,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('active-board-filters')), findsOneWidget);
    expect(find.text('FILTERED BY'), findsOneWidget);
    expect(find.text('PRIZEPICKS'), findsOneWidget);
    expect(find.text('PLAYABLE'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('clear-board-filters')));
    expect(cleared, isTrue);
  });

  testWidgets('takes no space when no filters are active', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ActiveBoardFilters(labels: const [], onClearAll: () {}),
      ),
    );

    expect(find.byKey(const ValueKey('active-board-filters')), findsNothing);
  });
}
