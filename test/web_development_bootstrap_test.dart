import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OneSignal is disabled safely on local development hosts', () {
    final service = File('web/onesignal-service.js').readAsStringSync();
    final pwa = File('web/pwa_install.js').readAsStringSync();

    for (final host in ['localhost', '127.0.0.1', '::1']) {
      expect(service, contains(host));
      expect(pwa, contains(host));
    }
    expect(service, contains('if (!enabled) return developmentResult();'));
    expect(service, contains('if (enabled)'));
    expect(pwa, contains("!isDevelopmentHost"));
  });
}
