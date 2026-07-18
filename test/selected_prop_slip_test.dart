import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/widgets/selected_prop_slip.dart';

void main() {
  testWidgets('active slip presents a simple review and build workflow', (
    tester,
  ) async {
    var removed = false;
    var cleared = false;
    var built = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 340,
            height: 760,
            child: SelectedPropSlip(
              props: const [
                SelectedProp(
                  id: 'prop-1',
                  playerName: 'Test Player',
                  team: 'TST',
                  position: 'NBA',
                  propType: 'Points',
                  gameTime: '7:00 PM',
                  sportsbook: 'Test Book',
                  imageUrl: '',
                  line: 24.5,
                  selectedSide: 'OVER',
                  edge: 4.8,
                  hitRate: 70,
                  bestOdds: -105,
                  liveOdds: -110,
                ),
              ],
              onRemove: (_) => removed = true,
              onClear: () async => cleared = true,
              onBuildTicket: () async => built = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('ACTIVE SLIP'), findsOneWidget);
    expect(find.text('Review your selections'), findsOneWidget);
    expect(find.text('READY TO BUILD'), findsOneWidget);
    expect(find.text('BUILD TICKET'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove player'));
    expect(removed, isTrue);

    await tester.tap(find.byTooltip('Clear active slip'));
    await tester.pump();
    expect(cleared, isTrue);

    await tester.tap(find.text('BUILD TICKET'));
    await tester.pump();
    expect(built, isTrue);
    expect(tester.takeException(), isNull);
  });
}
