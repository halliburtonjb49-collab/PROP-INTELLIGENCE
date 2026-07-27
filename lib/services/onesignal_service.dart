import 'onesignal_service_stub.dart'
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
  static const appId = '917b088b-4a9f-472d-8b52-3ab0d06ab98e';

  final OneSignalPlatform _platform = implementation.createOneSignalPlatform();
  bool _initialized = false;
  bool _verificationShown = false;

  Future<void> initialize() async {
    if (_initialized) return;
    await _platform.initialize(appId);
    _initialized = true;
  }

  void observeRegistration(void Function() onRegistered) {
    void evaluate(String? id) {
      if (!_verificationShown &&
          id != null &&
          id.isNotEmpty &&
          !id.startsWith('local-')) {
        _verificationShown = true;
        onRegistered();
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
