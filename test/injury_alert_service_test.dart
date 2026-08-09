import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/services/injury_alert_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('parses only injury impact realtime events', () {
    final parsed = parseInjuryAlertEvent('''
      {"type":"injury.impact.changed","eventId":"evt-1","data":{
        "level":"CRITICAL","title":"AVAILABILITY BLOCK","message":"Player out"
      }}
    ''');
    expect(parsed?['eventId'], 'evt-1');
    expect(parsed?['level'], 'CRITICAL');
    expect(parseInjuryAlertEvent('{"type":"props.updated"}'), isNull);
    expect(parseInjuryAlertEvent('not json'), isNull);
  });

  test('urgent-only preferences suppress watch and cleared interruptions', () {
    const preferences = InjuryAlertPreferences(criticalOnly: true);
    expect(
      shouldPresentInjuryAlert({'level': 'CRITICAL'}, preferences),
      isTrue,
    );
    expect(shouldPresentInjuryAlert({'level': 'HIGH'}, preferences), isTrue);
    expect(shouldPresentInjuryAlert({'level': 'WATCH'}, preferences), isFalse);
    expect(
      shouldPresentInjuryAlert({'level': 'CLEARED'}, preferences),
      isFalse,
    );
  });

  test('preferences persist enabled and urgent-only settings', () async {
    const saved = InjuryAlertPreferences(enabled: false, criticalOnly: true);
    await saved.save();
    final loaded = await InjuryAlertPreferences.load();
    expect(loaded.enabled, isFalse);
    expect(loaded.criticalOnly, isTrue);
  });
}
