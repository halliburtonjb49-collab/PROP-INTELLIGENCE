import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/widgets/builder_strategy_panel.dart';

Map<String, dynamic> _strategy({required bool enoughData}) => {
  'enough_data': enoughData,
  'resolved_legs': enoughData ? 24 : 4,
  'minimum_required_legs': 10,
  'recommended_sport': {'name': 'WNBA', 'hit_rate': 64.2, 'sample_size': 19},
  'recommended_prop_site': {
    'name': 'PrizePicks',
    'hit_rate': 61.5,
    'sample_size': 22,
  },
  'recommended_market': {'name': 'points', 'hit_rate': 66.7, 'sample_size': 15},
  'recommended_minimum_edge': 6,
  'recommended_minimum_confidence': 65,
  'recommended_leg_count': 4,
  'warnings': ['Avoid concentrating every leg in one game.'],
};

void main() {
  for (final size in <Size>[const Size(1100, 900), const Size(520, 900)]) {
    testWidgets('strategy panel is usable at ${size.width.toInt()}px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var applies = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BuilderStrategyPanel(
                isLoading: false,
                strategy: _strategy(enoughData: true),
                marketLabel: (value) => value == 'points' ? 'Points' : value,
                onApply: () => applies += 1,
              ),
            ),
          ),
        ),
      );

      expect(find.text('RECOMMENDED STRATEGY'), findsOneWidget);
      expect(find.text('DATA READY'), findsOneWidget);
      expect(find.text('WNBA'), findsOneWidget);
      expect(find.text('PrizePicks'), findsOneWidget);
      expect(find.text('Points'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('APPLY RECOMMENDED STRATEGY'));
      await tester.tap(find.text('APPLY RECOMMENDED STRATEGY'));
      expect(applies, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('strategy apply stays disabled until enough data exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BuilderStrategyPanel(
              isLoading: false,
              strategy: _strategy(enoughData: false),
              marketLabel: (value) => value,
              onApply: () => fail('disabled strategy should not apply'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('4/10 LEGS'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });
}
