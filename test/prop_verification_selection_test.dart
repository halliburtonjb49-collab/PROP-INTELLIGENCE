import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/prop_data.dart';

PropData _prop({
  bool selectable = true,
  List<String> reasons = const [],
  String status = 'verified',
  String? startTimeUtc,
}) {
  return PropData(
    id: 'p1',
    eventId: 'e1',
    apiSportsGameId: '',
    playerId: 'pl1',
    pick: 'Over',
    edge: 0.1,
    imagePath: '',
    player: 'Test Player',
    sport: 'MLB',
    matchup: 'Detroit Tigers @ Seattle Mariners',
    sportsbook: 'PRIZEPICKS',
    market: 'Batter Hits',
    line: 0.5,
    selectable: selectable,
    verificationStatus: status,
    verificationReasons: reasons,
    startTimeUtc:
        startTimeUtc ??
        DateTime.now().toUtc().add(const Duration(hours: 6)).toIso8601String(),
  );
}

void main() {
  test('an unverified prop cannot be selected', () {
    // The backend withholds props it cannot describe at all. What arrives
    // unverified is merely incomplete, and a pick built on that is a pick
    // built on nothing.
    final prop = _prop(
      selectable: false,
      status: 'unverified',
      reasons: const ['projection_missing'],
    );

    expect(prop.isSelectable, isFalse);
    expect(prop.selectionBlockedReason, 'No model projection yet for this prop.');
  });

  test('a verified prop is selectable before its game starts', () {
    expect(_prop().isSelectable, isTrue);
  });

  test('the game clock still closes selection on a verified prop', () {
    final started = _prop(
      startTimeUtc: DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 30))
          .toIso8601String(),
    );

    expect(started.isSelectable, isFalse);
    // The clock reason, not the verification one.
    expect(started.selectionBlockedReason, contains('game is starting'));
  });

  test('a payload without verification fields stays selectable', () {
    // Older responses predate verification and must not be treated as
    // unselectable.
    final prop = PropData.fromJson(const {
      'id': 'legacy',
      'player': 'Test Player',
      'sport': 'MLB',
      'matchup': 'Detroit Tigers @ Seattle Mariners',
      'sportsbook': 'PRIZEPICKS',
      'market': 'Batter Hits',
      'line': 0.5,
    });

    expect(prop.selectable, isTrue);
    expect(prop.verificationStatus, 'verified');
  });

  test('verification fields are read from the payload', () {
    final prop = PropData.fromJson(const {
      'id': 'x',
      'player': 'Test Player',
      'sport': 'MLB',
      'matchup': 'Detroit Tigers @ Seattle Mariners',
      'sportsbook': 'PRIZEPICKS',
      'market': 'Batter Hits',
      'line': 0.5,
      'selectable': false,
      'verificationStatus': 'unverified',
      'verificationReasons': ['projection_missing'],
    });

    expect(prop.selectable, isFalse);
    expect(prop.verificationStatus, 'unverified');
    expect(prop.verificationReasons, contains('projection_missing'));
  });
}
