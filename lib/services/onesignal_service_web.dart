import 'dart:js_interop';

import 'onesignal_service.dart';

@JS('PropIntelligenceOneSignal.requestPermission')
external JSPromise<JSBoolean> _requestPermission();

@JS('PropIntelligenceOneSignal.login')
external JSPromise<JSAny?> _login(JSString externalId);

@JS('PropIntelligenceOneSignal.logout')
external JSPromise<JSAny?> _logout();

@JS('PropIntelligenceOneSignal.setEmail')
external JSPromise<JSAny?> _setEmail(JSString email);

@JS('PropIntelligenceOneSignal.setTag')
external JSPromise<JSAny?> _setTag(JSString key, JSString value);

OneSignalPlatform createOneSignalPlatform() => _WebOneSignalPlatform();

class _WebOneSignalPlatform implements OneSignalPlatform {
  @override
  Future<void> initialize(String appId) async {}

  @override
  void observePushSubscription(void Function(String? id) listener) {}

  @override
  String? get pushSubscriptionId => null;

  @override
  Future<bool> requestPermission() async =>
      (await _requestPermission().toDart).toDart;

  @override
  void login(String externalId) {
    _login(externalId.toJS);
  }

  @override
  void logout() {
    _logout();
  }

  @override
  void setEmail(String email) {
    _setEmail(email.toJS);
  }

  @override
  void setSmsNumber(String number) {}

  @override
  void setTag(String key, String value) {
    _setTag(key.toJS, value.toJS);
  }
}
