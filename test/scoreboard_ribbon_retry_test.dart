import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/controllers/scoreboard_controller.dart';
import 'package:prop_intelligence/models/scoreboard_game.dart';
import 'package:prop_intelligence/services/app_sound_service.dart';
import 'package:prop_intelligence/services/scoreboard_service.dart';
import 'package:prop_intelligence/widgets/scoreboard_navigation_ribbon.dart';

class _EmptyScoreboardService extends ScoreboardService {
  _EmptyScoreboardService() : super(baseUrl: 'https://example.invalid');

  int fetches = 0;

  @override
  Future<List<ScoreboardGame>> fetchGames({required DateTime date}) async {
    fetches += 1;
    return const [];
  }
}

void main() {
  testWidgets('empty scoreboard exposes a working refresh action', (
    tester,
  ) async {
    final service = _EmptyScoreboardService();
    final controller = ScoreboardController(service: service);
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            child: ScoreboardNavigationRibbon(
              controller: controller,
              expanded: true,
              selectedSport: 'ALL',
              accentColor: Colors.amber,
              soundService: AppSoundService.instance,
              onExpandedChanged: (_) {},
              onSportSelected: (_) {},
              onOpenScoreboard: () {},
              onOpenGameMarkets: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('scoreboard-ribbon-retry')), findsOne);
    await tester.tap(find.byKey(const ValueKey('scoreboard-ribbon-retry')));
    await tester.pumpAndSettle();
    expect(service.fetches, 2);
    expect(tester.takeException(), isNull);
  });
}
