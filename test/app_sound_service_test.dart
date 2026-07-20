import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/services/app_sound_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sound preferences are persisted', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final service = AppSoundService.instance;

    await service.load();
    await service.setEnabled(false);
    await service.setProfile(AppSoundProfile.energetic);
    await service.setNavigationEnabled(false);
    await service.setSelectionEnabled(false);
    await service.setAlertsEnabled(false);
    await service.setVolume(.35);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('app_sounds_enabled'), isFalse);
    expect(preferences.getString('app_sound_profile'), 'energetic');
    expect(preferences.getBool('app_sound_navigation'), isFalse);
    expect(preferences.getBool('app_sound_selection'), isFalse);
    expect(preferences.getBool('app_sound_alerts'), isFalse);
    expect(preferences.getDouble('app_sound_volume'), .35);
  });
}
