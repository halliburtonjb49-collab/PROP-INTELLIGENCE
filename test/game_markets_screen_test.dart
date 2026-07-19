import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/screens/game_markets_screen.dart';
import 'package:prop_intelligence/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('game markets restore instantly from device cache', () async {
    SharedPreferences.setMockInitialValues({
      'game-market-feed-v1-MLB':
          '{"sport":"MLB","updatedAt":"2026-07-19T20:00:00Z","events":[{"id":"g1","sport":"MLB","league":"MLB","homeTeam":"Home","awayTeam":"Away","commenceTime":"2026-07-20T00:00:00Z","bookmakers":[]}]}',
    });
    final cached = await ApiService().loadCachedGameMarkets('MLB');
    expect(cached, isNotNull);
    expect(cached!.cached, true);
    expect(cached.events.single.id, 'g1');
  });

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
      expect(find.text('MONEYLINE'), findsWidgets);
      expect(find.text('SPREADS'), findsWidgets);
      expect(find.text('GAME TOTALS'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
