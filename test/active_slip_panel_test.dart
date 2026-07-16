import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prop_intelligence/controllers/active_slip_controller.dart';
import 'package:prop_intelligence/widgets/active_slip_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders active ticket header and actions', (tester) async {
    final controller = ActiveSlipController();
    await controller.load();
    await controller.addLegs([
      {
        'prop_id': 'p1',
        'player': 'A Player',
        'sport': 'NBA',
        'market': 'points',
        'side': 'OVER',
        'line': 20.5,
        'original_line': 20.5,
        'current_line': 22.0,
        'odds': -110,
        'current_odds': -125,
        'edge': 64,
        'confidence': 68,
        'custom_label': 'Best Bet',
        'manual_note': 'Great matchup tonight',
        'movement_status': 'WORSE',
        'result_status': 'won',
        'result_value': 24.0,
        'prop_site': 'PrizePicks',
        'matchup': 'LAL @ BOS',
      },
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 700,
            child: ActiveSlipPanel(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1-PICK ENTRY'), findsOneWidget);
    expect(find.text('A Player'), findsOneWidget);
    expect(find.text('MORE 22.0'), findsOneWidget);
    expect(find.text('VIEW / LOCK ENTRY'), findsOneWidget);
  });
}
