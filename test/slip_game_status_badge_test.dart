import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/widgets/slip_history_panel.dart';

void main() {
  testWidgets('recognizes live game status aliases', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: GameStatusBadge(status: 'InProgress')),
    );
    expect(find.textContaining('LIVE'), findsOneWidget);
  });

  testWidgets('recognizes final game status aliases', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: GameStatusBadge(status: 'Final')),
    );
    expect(find.text('FINAL'), findsOneWidget);
  });
  testWidgets('shows live quarter and clock with progress status', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GameStatusBadge(status: 'Live', detail: 'Q3 • 4:21'),
      ),
    );
    expect(find.textContaining('LIVE • Q3 • 4:21'), findsOneWidget);
  });
}
