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

  test('production keeps the versioned workspace service worker', () {
    final buildScript = File('vercel_build.sh').readAsStringSync();
    final worker = File('web/OneSignalSDKWorker.js').readAsStringSync();
    final pwa = File('web/pwa_install.js').readAsStringSync();

    expect(
      buildScript,
      isNot(contains(
        'cp web/legacy_service_worker.js build/site/OneSignalSDKWorker.js',
      )),
    );
    expect(worker, contains("event.data.type === 'PI_ACTIVATE_UPDATE'"));
    expect(worker, contains('self.skipWaiting()'));
    expect(pwa, contains("getRegistration('/workspace/')"));
    expect(pwa, contains('window.setTimeout(reloadCurrentRelease, 4000)'));
  });
}
