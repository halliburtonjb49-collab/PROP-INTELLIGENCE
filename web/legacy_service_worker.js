// Neutralizes service workers installed by the former split-domain deployment.
// Do not unregister or navigate active clients here: iOS Chrome may keep a
// controlled tab alive after an update, and forcing navigation while that tab
// resumes produces a browser-level "Can't open this page" failure.
const LEGACY_CACHE_PREFIXES = ['flutter-app-cache', 'flutter-temp-cache'];

self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys
      .filter((key) => LEGACY_CACHE_PREFIXES.some((prefix) => key.startsWith(prefix)))
      .map((key) => caches.delete(key)));
    await self.clients.claim();
  })());
});
