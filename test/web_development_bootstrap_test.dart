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

  test('production keeps exactly one versioned workspace service worker', () {
    final buildScript = File('vercel_build.sh').readAsStringSync();
    final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();
    final worker = File('web/OneSignalSDKWorker.js').readAsStringSync();
    final pwa = File('web/pwa_install.js').readAsStringSync();

    expect(
      buildScript,
      isNot(
        contains(
          'cp web/legacy_service_worker.js build/site/OneSignalSDKWorker.js',
        ),
      ),
    );
    expect(worker, contains("event.data.type === 'PI_ACTIVATE_UPDATE'"));
    expect(worker, contains('self.skipWaiting()'));
    expect(bootstrap, isNot(contains('serviceWorkerSettings')));
    expect(pwa, contains("getRegistration('/workspace/')"));
    expect(pwa, contains("serviceWorker.register("));
    expect(
      pwa,
      contains(
        "worker.scriptURL.includes('/workspace/flutter_service_worker.js')",
      ),
    );
    expect(
      pwa,
      isNot(contains("const cleanupKey = 'pi-mobile-direct-release'")),
    );
    expect(pwa, contains('reloadCurrentRelease();'));
  });

  test('legacy root worker never navigates or unregisters active clients', () {
    final worker = File('web/legacy_service_worker.js').readAsStringSync();

    expect(worker, contains('self.clients.claim()'));
    expect(worker, isNot(contains('client.navigate(')));
    expect(worker, isNot(contains('self.registration.unregister()')));
    expect(worker, isNot(contains('Response.redirect(')));
  });
}
