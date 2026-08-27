import 'onesignal_service_stub.dart'
    if (dart.library.js_interop) 'onesignal_service_web.dart'
    if (dart.library.io) 'onesignal_service_mobile.dart'
    as implementation;

abstract interface class OneSignalPlatform {
  Future<void> initialize(String appId);
  void observePushSubscription(void Function(String? id) listener);
  String? get pushSubscriptionId;
  Future<bool> requestPermission();
  void login(String externalId);
  void logout();
  void setEmail(String email);
  void setSmsNumber(String number);
  void setTag(String key, String value);
}

class OneSignalService {
  OneSignalService._();

  static final OneSignalService instance = OneSignalService._();
  static const appId = 'b7d55e15-969b-40c2-b7d4-62e6c201e7d9';

  final OneSignalPlatform _platform = implementation.createOneSignalPlatform();
  bool _initialized = false;
  String? _lastRegistrationId;

  Future<void> initialize() async {
    if (_initialized) return;
    await _platform.initialize(appId);
    _initialized = true;
  }

  void observeRegistration(void Function(String id) onRegistered) {
    void evaluate(String? id) {
      if (id != null &&
          id.isNotEmpty &&
          !id.startsWith('local-') &&
          id != _lastRegistrationId) {
        _lastRegistrationId = id;
        onRegistered(id);
      }
    }

    _platform.observePushSubscription(evaluate);
    evaluate(_platform.pushSubscriptionId);
  }

  Future<bool> requestPermission() => _platform.requestPermission();
  void login(String externalId) => _platform.login(externalId);
  void logout() => _platform.logout();
  void setEmail(String email) => _platform.setEmail(email);
  void setSmsNumber(String number) => _platform.setSmsNumber(number);
  void setTag(String key, String value) => _platform.setTag(key, value);
}
