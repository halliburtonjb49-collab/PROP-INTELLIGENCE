import 'package:flutter/foundation.dart';

class DeveloperModeService {
  DeveloperModeService._();

  static const bool _enabledByDefine = bool.fromEnvironment(
    'ENABLE_DEV_BYPASS',
    defaultValue: false,
  );
  static const String _pinByDefine = String.fromEnvironment(
    'DEV_BYPASS_PIN',
    defaultValue: '',
  );

  static final ValueNotifier<bool> unlocked = ValueNotifier<bool>(false);

  static bool get canShowEntry =>
      kDebugMode && _enabledByDefine && _pinByDefine.trim().isNotEmpty;

  static bool unlock(String pin) {
    if (!canShowEntry) {
      return false;
    }
    final ok = pin.trim() == _pinByDefine.trim();
    if (ok) {
      unlocked.value = true;
    }
    return ok;
  }

  static void lock() {
    unlocked.value = false;
  }
}
