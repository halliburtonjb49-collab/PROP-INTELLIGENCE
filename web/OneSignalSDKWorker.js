// OneSignal Website SDK v16 service worker (stable release 160608).
importScripts("https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.sw.js");

const PI_BUILD = '__PI_BUILD_VERSION__';
const PI_CACHE_PREFIX = 'pi-app-shell-';
const PI_CACHE = `${PI_CACHE_PREFIX}${PI_BUILD}`;
const PI_MAX_CACHE_ENTRIES = 120;
const PI_APP_SHELL = [
  '/',
  '/index.html',
  '/offline.html',
  '/manifest.json',
  '/flutter_bootstrap.js',
  '/favicon.png',
  '/icons/Icon-192.png',
  '/icons/Icon-512.png',
  '/icons/apple-touch-icon-180.png',
  '/icons/Icon-maskable-safe-192.png',
  '/icons/Icon-maskable-safe-512.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(PI_CACHE)
      .then((cache) => cache.addAll(PI_APP_SHELL))
      .then(() => self.skipWaiting()),
  );
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
    if (hadPreviousRelease) {
      const clients = await self.clients.matchAll({type: 'window'});
      clients.forEach((client) => client.postMessage({type: 'PI_UPDATE_READY'}));
    }
  })());
});

async function trimCache(cache) {
  const keys = await cache.keys();
  await Promise.all(keys.slice(0, Math.max(0, keys.length - PI_MAX_CACHE_ENTRIES))
    .map((request) => cache.delete(request)));
}

async function networkFirstAsset(request) {
  const cache = await caches.open(PI_CACHE);
  try {
    const response = await fetch(request, {cache: 'no-store'});
    if (response.ok) await cache.put(request, response.clone());
    return response;
  } catch (_) {
    const cached = await cache.match(request);
    if (cached) return cached;
    throw _;
  }
}

async function navigationResponse(request) {
  const cache = await caches.open(PI_CACHE);
  try {
    const response = await fetch(request);
    if (response.ok) await cache.put('/index.html', response.clone());
    return response;
  } catch (_) {
    return (await cache.match('/index.html')) || (await cache.match('/offline.html'));
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
  if (url.origin === self.location.origin && !url.pathname.includes('OneSignalSDKWorker.js')) {
    // Every Flutter asset is release-coupled. Network-first prevents an old
    // main.dart.js, CanvasKit file, font, or asset manifest from being mixed
    // with a newly deployed shell. The release cache remains an offline-only
    // fallback and is never preferred while production is reachable.
    event.respondWith(networkFirstAsset(request));
  }
});
