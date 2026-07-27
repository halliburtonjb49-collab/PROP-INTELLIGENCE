import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import 'onesignal_service.dart';

OneSignalPlatform createOneSignalPlatform() => _MobileOneSignalPlatform();

class _MobileOneSignalPlatform implements OneSignalPlatform {
  void Function(OSPushSubscriptionChangedState)? _subscriptionObserver;
  bool get _supported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Future<void> initialize(String appId) async {
    if (!_supported) return;
    OneSignal.Debug.setLogLevel(
      kDebugMode ? OSLogLevel.verbose : OSLogLevel.none,
    );
    OneSignal.initialize(appId);
  }

  @override
  void observePushSubscription(void Function(String? id) listener) {
    if (!_supported) return;
    _subscriptionObserver = (state) => listener(state.current.id);
    OneSignal.User.pushSubscription.addObserver(_subscriptionObserver!);
  }

  @override
  String? get pushSubscriptionId =>
      _supported ? OneSignal.User.pushSubscription.id : null;

  @override
  Future<bool> requestPermission() async =>
      _supported ? OneSignal.Notifications.requestPermission(true) : false;

  @override
  void login(String externalId) {
    if (_supported) OneSignal.login(externalId);
  }

  @override
  void logout() {
    if (_supported) OneSignal.logout();
  }

  @override
  void setEmail(String email) {
    if (_supported) OneSignal.User.addEmail(email);
  }

  @override
  void setSmsNumber(String number) {
    if (_supported) OneSignal.User.addSms(number);
  }

  @override
  void setTag(String key, String value) {
    if (_supported) OneSignal.User.addTagWithKey(key, value);
  }
}
