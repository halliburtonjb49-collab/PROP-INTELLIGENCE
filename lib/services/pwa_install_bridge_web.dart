import 'dart:js_interop';

@JS('isPwaInstallAvailable')
external bool _isPwaInstallAvailable();

@JS('isIosPwaDevice')
external bool _isIosPwaDevice();

@JS('triggerPwaInstall')
external JSPromise<JSString> _triggerPwaInstall();

Future<String> triggerPwaInstall() async {
  final outcome = await _triggerPwaInstall().toDart;
  return outcome.toDart;
}

bool isPwaInstallAvailable() => _isPwaInstallAvailable();

bool isIosPwaDevice() => _isIosPwaDevice();
