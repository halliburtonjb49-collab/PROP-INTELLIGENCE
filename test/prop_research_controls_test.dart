import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/prop_data.dart';
import 'package:prop_intelligence/widgets/prop_research_controls.dart';

void main() {
  testWidgets('research toggle reflects state and invokes its callback', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResearchToggle(open: false, onTap: () => taps += 1),
        ),
      ),
    );

    expect(find.text('SHOW RESEARCH'), findsOneWidget);
    await tester.tap(find.text('SHOW RESEARCH'));
    expect(taps, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResearchToggle(open: true, onTap: () => taps += 1),
        ),
      ),
    );
    expect(find.text('HIDE RESEARCH'), findsOneWidget);
  });

  testWidgets('PI verdict summarizes action facts and recheck guidance', (
    tester,
  ) async {
    const verdict = PropVerdict(
      decision: 'PLAY_NOW',
      headline: 'PLAY OVER',
      reason: 'Projection clears the current line.',
      confidence: 82,
      maximumPlayableLine: 24.5,
      betterPriceAt: 'PRIZEPICKS',
      recheck: 'AFTER LINEUPS',
      actionable: true,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PiVerdictBlock(verdict: verdict)),
      ),
    );

    expect(find.text('PI VERDICT'), findsOneWidget);
    expect(find.text('PLAY OVER'), findsOneWidget);
    expect(find.text('Projection clears the current line.'), findsOneWidget);
    expect(find.textContaining('verdict confidence'), findsNothing);
    expect(find.textContaining('playable to 24.5'), findsOneWidget);
    expect(find.textContaining('better at PRIZEPICKS'), findsOneWidget);
    expect(find.text('Recheck after lineups'), findsOneWidget);
  });

  testWidgets('PI verdict omits empty optional facts', (tester) async {
    const verdict = PropVerdict(
      decision: 'PASS',
      headline: 'PASS',
      reason: 'No verified edge.',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PiVerdictBlock(verdict: verdict)),
      ),
    );

    expect(find.byKey(const ValueKey('pi-verdict-facts')), findsNothing);
    expect(find.text('PASS'), findsOneWidget);
  });

  testWidgets('phone verdict keeps a concise visible summary', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const reason =
        'The projection clears the current line, but users should confirm '
        'availability and recent lineup news before making a decision.';
    const verdict = PropVerdict(
      decision: 'LEAN',
      headline: 'LEAN OVER',
      reason: reason,
      confidence: 67,
      maximumPlayableLine: 17.5,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PiVerdictBlock(verdict: verdict)),
      ),
    );

    expect(tester.widget<Text>(find.text(reason)).maxLines, 3);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('pi-verdict-facts')))
          .maxLines,
      1,
    );
    expect(tester.takeException(), isNull);
  });
}
