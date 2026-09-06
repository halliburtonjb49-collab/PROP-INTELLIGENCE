import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CanvasKit engine is reused across repeat launches', () {
    final config = jsonDecode(File('vercel.json').readAsStringSync()) as Map;
    final headers = (config['headers'] as List).whereType<Map>();
    final canvasKit = headers.singleWhere(
      (entry) => entry['source'] == '/workspace/canvaskit/(.*)',
    );
    final values = (canvasKit['headers'] as List)
        .whereType<Map>()
        .map((entry) => entry['value']?.toString() ?? '')
        .toList(growable: false);
    expect(values, isNotEmpty);
    expect(values.every((value) => value.contains('max-age=86400')), isTrue);
    expect(
      values.every((value) => value.contains('stale-while-revalidate')),
      isTrue,
    );
  });
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

  test('OneSignal uses the production web application identity', () {
    final service = File('web/onesignal-service.js').readAsStringSync();

    expect(service, contains('b7d55e15-969b-40c2-b7d4-62e6c201e7d9'));
    expect(service, isNot(contains('917b088b-4a9f-472d-8b52-3ab0d06ab98e')));
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
    expect(worker, contains('`\${PI_ROOT}/main.dart.js`'));
    expect(worker, contains('`\${PI_ROOT}/canvaskit/canvaskit.wasm`'));
    expect(worker, contains('cacheFirstReleaseAsset(request)'));
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
