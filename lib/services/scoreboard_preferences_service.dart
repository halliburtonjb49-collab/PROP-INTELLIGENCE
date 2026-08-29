import 'package:shared_preferences/shared_preferences.dart';

class ScoreboardPreferencesService {
  static const _autoRotateKey = 'pi_scoreboard_auto_rotate';
  static const _expandedKey = 'pi_scoreboard_expanded';
  static const _sportsKey = 'pi_scoreboard_favorite_sports';

  Future<bool> autoRotate() async =>
      (await SharedPreferences.getInstance()).getBool(_autoRotateKey) ?? true;

  Future<bool> expanded() async =>
      (await SharedPreferences.getInstance()).getBool(_expandedKey) ?? true;

  Future<Set<String>> favoriteSports() async => {
    ...?((await SharedPreferences.getInstance()).getStringList(_sportsKey)),
  };

  Future<void> setAutoRotate(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_autoRotateKey, value);

  Future<void> setExpanded(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_expandedKey, value);

  Future<void> setFavoriteSports(Set<String> value) async =>
      (await SharedPreferences.getInstance()).setStringList(
        _sportsKey,
        value.toList()..sort(),
      );
}
