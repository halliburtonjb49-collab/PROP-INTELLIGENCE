import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppSoundEvent { button, navigation, selection, success, warning }

enum AppSoundProfile {
  subtle('Subtle', 'Quiet feedback for essential actions only'),
  balanced('Balanced', 'Clear feedback without being distracting'),
  energetic('Energetic', 'More expressive feedback for every action');

  const AppSoundProfile(this.label, this.description);
  final String label;
  final String description;
}

class AppSoundService extends ChangeNotifier {
  AppSoundService._();
  static final AppSoundService instance = AppSoundService._();

  static const _enabledKey = 'app_sounds_enabled';
  static const _profileKey = 'app_sound_profile';
  static const _volumeKey = 'app_sound_volume';
  static const _navigationKey = 'app_sound_navigation';
  static const _selectionKey = 'app_sound_selection';
  static const _alertsKey = 'app_sound_alerts';

  bool _enabled = true;
  bool _navigationEnabled = true;
  bool _selectionEnabled = true;
  bool _alertsEnabled = true;
  AppSoundProfile _profile = AppSoundProfile.balanced;
  double _volume = .65;
  bool _loaded = false;
  final Map<String, Uint8List> _toneCache = {};
  final Map<String, Future<AudioPool>> _poolCache = {};

  bool get enabled => _enabled;
  bool get navigationEnabled => _navigationEnabled;
  bool get selectionEnabled => _selectionEnabled;
  bool get alertsEnabled => _alertsEnabled;
  AppSoundProfile get profile => _profile;
  double get volume => _volume;

  Future<void> load() async {
    if (_loaded) return;
    final preferences = await SharedPreferences.getInstance();
    _enabled = preferences.getBool(_enabledKey) ?? true;
    _navigationEnabled = preferences.getBool(_navigationKey) ?? true;
    _selectionEnabled = preferences.getBool(_selectionKey) ?? true;
    _alertsEnabled = preferences.getBool(_alertsKey) ?? true;
    _volume = preferences.getDouble(_volumeKey) ?? .65;
    final storedProfile = preferences.getString(_profileKey);
    _profile = AppSoundProfile.values.firstWhere(
      (profile) => profile.name == storedProfile,
      orElse: () => AppSoundProfile.balanced,
    );
    _loaded = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey, value);
    if (value) unawaited(play(AppSoundEvent.success, force: true));
  }

  Future<void> setProfile(AppSoundProfile value) async {
    _profile = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_profileKey, value.name);
    unawaited(play(AppSoundEvent.success));
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0).toDouble();
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(_volumeKey, _volume);
  }

  Future<void> setNavigationEnabled(bool value) =>
      _setPreference(_navigationKey, value, () => _navigationEnabled = value);
  Future<void> setSelectionEnabled(bool value) =>
      _setPreference(_selectionKey, value, () => _selectionEnabled = value);
  Future<void> setAlertsEnabled(bool value) =>
      _setPreference(_alertsKey, value, () => _alertsEnabled = value);

  Future<void> _setPreference(
    String key,
    bool value,
    VoidCallback update,
  ) async {
    update();
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(key, value);
  }

  Future<void> play(AppSoundEvent event, {bool force = false}) async {
    if ((!_enabled && !force) || !_eventEnabled(event)) return;
    if (_profile == AppSoundProfile.subtle &&
        event != AppSoundEvent.success &&
        event != AppSoundEvent.warning) {
      return;
    }

    if (_volume <= 0) return;
    final cacheKey = '${_profile.name}:${event.name}';
    try {
      final pool = await (_poolCache[cacheKey] ??= AudioPool.create(
        source: BytesSource(
          _toneCache.putIfAbsent(cacheKey, () => _toneFor(event)),
        ),
        minPlayers: 1,
        maxPlayers: 3,
      ));
      await pool.start(volume: _volume);
    } catch (_) {
      _poolCache.remove(cacheKey);
    }
  }

  Uint8List _toneFor(AppSoundEvent event) {
    final (frequency, duration) = switch (event) {
      AppSoundEvent.button => (610.0, .045),
      AppSoundEvent.navigation => (520.0, .055),
      AppSoundEvent.selection => (690.0, .075),
      AppSoundEvent.success => (
        _profile == AppSoundProfile.energetic ? 940.0 : 820.0,
        .15,
      ),
      AppSoundEvent.warning => (310.0, .20),
    };
    return _createWave(frequency: frequency, durationSeconds: duration);
  }

  Uint8List _createWave({
    required double frequency,
    required double durationSeconds,
  }) {
    const sampleRate = 22050;
    const channels = 1;
    const bitsPerSample = 16;
    final sampleCount = (sampleRate * durationSeconds).round();
    final dataSize = sampleCount * 2;
    final bytes = ByteData(44 + dataSize);

    void ascii(int offset, String value) {
      for (var index = 0; index < value.length; index++) {
        bytes.setUint8(offset + index, value.codeUnitAt(index));
      }
    }

    ascii(0, 'RIFF');
    bytes.setUint32(4, 36 + dataSize, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, channels, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, bitsPerSample, Endian.little);
    ascii(36, 'data');
    bytes.setUint32(40, dataSize, Endian.little);

    for (var sample = 0; sample < sampleCount; sample++) {
      final progress = sample / sampleCount;
      final envelope = math.sin(math.pi * progress);
      final harmonic = _harmonic(frequency, sample / sampleRate);
      final value = (harmonic * envelope * 15000).round().clamp(-32768, 32767);
      bytes.setInt16(44 + (sample * 2), value, Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  double _harmonic(double frequency, double time) {
    final fundamental = math.sin(2 * math.pi * frequency * time);
    final overtone = math.sin(2 * math.pi * frequency * 2 * time) * .18;
    return fundamental + overtone;
  }

  bool _eventEnabled(AppSoundEvent event) => switch (event) {
    AppSoundEvent.button => _selectionEnabled,
    AppSoundEvent.navigation => _navigationEnabled,
    AppSoundEvent.selection => _selectionEnabled,
    AppSoundEvent.success || AppSoundEvent.warning => _alertsEnabled,
  };
}
