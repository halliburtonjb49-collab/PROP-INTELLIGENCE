import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/widgets/context_research_panel.dart';

void main() {
  testWidgets('context research exposes verified basketball Stat Slam inputs', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ContextResearchPanel(sport: 'NBA')),
      ),
    );

    expect(find.text('CONTEXT RESEARCH'), findsOneWidget);
    expect(find.text('PTS'), findsOneWidget);
    expect(find.text('REB'), findsOneWidget);
    expect(find.text('AST'), findsOneWidget);
    expect(find.text('RUN STAT SLAM'), findsOneWidget);
  });

  testWidgets('unsupported sports explain why Stat Slam is unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ContextResearchPanel(sport: 'NFL')),
      ),
    );

    expect(
      find.textContaining('currently available for NBA and WNBA'),
      findsOneWidget,
    );
    expect(find.text('RUN STAT SLAM'), findsNothing);
  });
}
