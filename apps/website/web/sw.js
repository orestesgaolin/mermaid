// Network-first service worker for the comparison demo. The Jaspr and Flutter
// bundles have stable (un-hashed) filenames, so without this a returning
// visitor would run a stale cached build (e.g. the layout picker would have no
// effect because embed_bridge.js / the Flutter bundle were cached). Network-
// first guarantees the latest deploy is used whenever the user is online, with
// the cache only as an offline fallback.
const CACHE = 'mermaid-dart-demo-v1';

self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) {
      if (key !== CACHE) await caches.delete(key);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  event.respondWith((async () => {
    try {
      const fresh = await fetch(req, { cache: 'no-store' });
      const cache = await caches.open(CACHE);
      cache.put(req, fresh.clone());
      return fresh;
    } catch (err) {
      const cached = await caches.match(req);
      if (cached) return cached;
      throw err;
    }
  })());
});
