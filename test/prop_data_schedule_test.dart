import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/prop_data.dart';

PropData scheduledProp(String startTimeUtc) => PropData(
  id: 'pitcher-strikeouts',
  eventId: 'game-1',
  apiSportsGameId: '',
  playerId: 'pitcher-1',
  player: 'Pitcher One',
  sport: 'MLB',
  matchup: 'Away @ Home',
  sportsbook: 'FanDuel',
  market: 'Pitcher Strikeouts',
  startTimeUtc: startTimeUtc,
  gameStartTime: startTimeUtc,
  line: 6.5,
  pick: 'OVER',
  edge: 4,
  imagePath: '',
);

void main() {
  test('scheduled prop exposes local day, date, and game time', () {
    final prop = scheduledProp('2030-07-30T23:10:00Z');

    expect(prop.localGameDateTimeDisplay, contains('•'));
    expect(prop.localGameDateTimeDisplay, isNot(contains('GAME TIME PENDING')));
  });

  test('started prop cannot be selected', () {
    final prop = scheduledProp('2020-07-30T23:10:00Z');

    expect(prop.gameHasStarted, isTrue);
    expect(prop.isSelectable, isFalse);
  });
}
