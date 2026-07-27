import 'onesignal_service.dart';

OneSignalPlatform createOneSignalPlatform() => _NoopOneSignalPlatform();

class _NoopOneSignalPlatform implements OneSignalPlatform {
  @override
  Future<void> initialize(String appId) async {}
  @override
  void observePushSubscription(void Function(String? id) listener) {}
  @override
  String? get pushSubscriptionId => null;
  @override
  Future<bool> requestPermission() async => false;
  @override
  void login(String externalId) {}
  @override
  void logout() {}
  @override
  void setEmail(String email) {}
  @override
  void setSmsNumber(String number) {}
  @override
  void setTag(String key, String value) {}
}
