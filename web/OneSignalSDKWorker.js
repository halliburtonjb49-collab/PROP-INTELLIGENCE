// OneSignal Website SDK v16 service worker (stable release 160608).
importScripts("https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.sw.js");

const PI_BUILD = '__PI_BUILD_VERSION__';
const PI_CACHE_PREFIX = 'pi-app-shell-';
const PI_CACHE = `${PI_CACHE_PREFIX}${PI_BUILD}`;
const PI_MAX_CACHE_ENTRIES = 120;
const PI_ROOT = '/workspace';
const PI_APP_SHELL = [
  `${PI_ROOT}/`,
  `${PI_ROOT}/index.html`,
  `${PI_ROOT}/offline.html`,
  `${PI_ROOT}/manifest.json`,
  `${PI_ROOT}/flutter_bootstrap.js`,
  `${PI_ROOT}/main.dart.js`,
  `${PI_ROOT}/canvaskit/canvaskit.js`,
  `${PI_ROOT}/canvaskit/canvaskit.wasm`,
  `${PI_ROOT}/favicon.png`,
  `${PI_ROOT}/icons/Icon-192.png`,
  `${PI_ROOT}/icons/Icon-512.png`,
  `${PI_ROOT}/icons/apple-touch-icon-180.png`,
  `${PI_ROOT}/icons/Icon-maskable-safe-192.png`,
  `${PI_ROOT}/icons/Icon-maskable-safe-512.png`,
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      await caches.open(PI_CACHE)
        .then((cache) => cache.addAll(PI_APP_SHELL));
      // Chrome, especially an installed iOS/Android PWA, can leave a newly
      // deployed worker waiting behind the previous app shell indefinitely.
      // Activate this release immediately; pwa_install.js already listens for
      // controllerchange and reloads with the current release identifier.
      await self.skipWaiting();
    })(),
  );
});

self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'PI_ACTIVATE_UPDATE') self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    const hadPreviousRelease = keys.some(
      (key) => key.startsWith(PI_CACHE_PREFIX) && key !== PI_CACHE,
    );
    await Promise.all(keys
      .filter((key) => key.startsWith(PI_CACHE_PREFIX) && key !== PI_CACHE)
      .map((key) => caches.delete(key)));
    await self.clients.claim();
    void hadPreviousRelease;
  })());
});

async function trimCache(cache) {
  const keys = await cache.keys();
  await Promise.all(keys.slice(0, Math.max(0, keys.length - PI_MAX_CACHE_ENTRIES))
    .map((request) => cache.delete(request)));
}

async function cacheFirstReleaseAsset(request) {
  const cache = await caches.open(PI_CACHE);
  const cached = await cache.match(request);
  if (cached) return cached;
  const response = await fetch(request);
  if (response.ok) {
    await cache.put(request, response.clone());
    await trimCache(cache);
  }
  return response;
}

async function navigationResponse(request) {
  const cache = await caches.open(PI_CACHE);
  try {
    const response = await fetch(request, {cache: 'no-store'});
    if (response.ok) await cache.put(`${PI_ROOT}/index.html`, response.clone());
    return response;
  } catch (_) {
    return (await cache.match(`${PI_ROOT}/index.html`)) ||
      (await cache.match(`${PI_ROOT}/offline.html`));
  }
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  if (request.mode === 'navigate') {
    event.respondWith(navigationResponse(request));
    return;
  }
  const url = new URL(request.url);
  const isStaticWorkspaceAsset = url.pathname.startsWith(`${PI_ROOT}/`) &&
    !url.pathname.includes('/api/') &&
    /\.(?:js|css|json|png|jpe?g|webp|svg|gif|ico|woff2?|ttf|wasm|bin)$/i
      .test(url.pathname);
  if (url.origin === self.location.origin && isStaticWorkspaceAsset &&
      !url.pathname.includes('OneSignalSDKWorker.js')) {
    // PI_CACHE includes the commit SHA, so a cached asset can only belong to
    // this worker's release. Reusing it avoids downloading and compiling the
    // 5.5 MB Flutter program plus CanvasKit on every login. A new release gets
    // a new cache and preloads its runtime before this worker activates.
    event.respondWith(cacheFirstReleaseAsset(request));
  }
});
