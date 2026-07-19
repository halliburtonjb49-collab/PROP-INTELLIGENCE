import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/screens/game_markets_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final device in <String, Size>{
    'phone portrait': const Size(390, 844),
    'android tablet portrait': const Size(800, 1280),
    'ipad portrait': const Size(1024, 1366),
    'ipad landscape': const Size(1366, 1024),
  }.entries) {
    testWidgets('game markets fits ${device.key}', (tester) async {
      tester.view.physicalSize = device.value;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(body: GameMarketsScreen(onAddToSlip: (_) async => 1)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('GAME MARKETS'), findsOneWidget);
      expect(find.text('MONEYLINE'), findsOneWidget);
      expect(find.text('SPREADS'), findsOneWidget);
      expect(find.text('GAME TOTALS'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
