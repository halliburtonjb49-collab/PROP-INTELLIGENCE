{{flutter_js}}
{{flutter_build_config}}

// Flutter's former app-shell service worker can keep an older interface alive
// after a production deployment. Remove only Flutter's worker/cache (OneSignal
// uses a separate worker and remains registered), then load the current bundle.
(async () => {
  if ('serviceWorker' in navigator) {
    const registrations = await navigator.serviceWorker.getRegistrations();
    await Promise.all(
      registrations
        .filter((registration) => {
          const url = registration.active?.scriptURL ??
            registration.waiting?.scriptURL ??
            registration.installing?.scriptURL ?? '';
          return url.includes('flutter_service_worker.js');
        })
        .map((registration) => registration.unregister()),
    );
  }

  if ('caches' in window) {
    const keys = await caches.keys();
    await Promise.all(
      keys
        .filter((key) => key.startsWith('flutter-app-cache'))
        .map((key) => caches.delete(key)),
    );
  }

  // CanvasKit keeps PI's compact typography, thin borders, and sports imagery
  // consistently sharp across browser zoom levels and high-DPI displays.
  await _flutter.loader.load({
    config: {
      renderer: 'canvaskit',
    },
  });
})();
