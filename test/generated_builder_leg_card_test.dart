import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/widgets/generated_builder_leg_card.dart';

void main() {
  testWidgets('generated leg card preserves every research action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final calls = <String>[];
    final leg = <String, dynamic>{
      'player': 'Test Player',
      'side': 'OVER',
      'line': 24.5,
      'original_line': 24.5,
      'current_line': 25.5,
      'market': 'points',
      'prop_site': 'PrizePicks',
      'edge': 7.2,
      'confidence': 68,
      'matchup': 'CHI at NY',
      'custom_label': 'Best angle',
      'manual_note': 'Verify the starting lineup.',
      'movement_status': 'BETTER',
      'original_odds': -110,
      'current_odds': 105,
      'last_line_check': 'now',
      'historical_hit_rate': 62.5,
    };

    final card = GeneratedBuilderLegCard(
      subtreeKey: const ValueKey('generated-leg-test'),
      leg: leg,
      index: 0,
      propId: 'test-prop',
      isSelected: false,
      isLocked: false,
      isWatchlisted: false,
      isInActiveSlip: false,
      isLoadingWatchlist: false,
      isReplacing: false,
      isEditingNote: false,
      isExplanationExpanded: false,
      explanationPanel: const Text(
        'Expanded research',
        key: ValueKey('expanded-research'),
      ),
      onRemoveFromSlip: () => calls.add('remove'),
      onToggleSelection: () => calls.add('add'),
      onToggleLock: () => calls.add('lock'),
      onToggleWatchlist: () => calls.add('watch'),
      onReplace: () => calls.add('replace'),
      onEditNote: () => calls.add('note'),
      onShowLabelMenu: () => calls.add('label'),
      onToggleExplanation: () => calls.add('explain'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: card)),
      ),
    );

    expect(find.text('Test Player'), findsOneWidget);
    expect(find.text('Current: OVER 25.5 points'), findsOneWidget);
    expect(find.text('Built at: OVER 24.5'), findsOneWidget);
    expect(find.text('Verify the starting lineup.'), findsOneWidget);
    expect(find.byKey(const ValueKey('expanded-research')), findsNothing);

    for (final action in <String>[
      'ADD',
      'LOCK PICK',
      'WATCHLIST',
      'REPLACE',
      'ADD NOTE',
      'LABEL',
      'WHY THIS PICK?',
    ]) {
      await tester.tap(find.text(action));
      await tester.pump();
    }

    expect(calls, [
      'add',
      'lock',
      'watch',
      'replace',
      'note',
      'label',
      'explain',
    ]);
    expect(tester.takeException(), isNull);
  });
}
