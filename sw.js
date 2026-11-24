/* BizKipe service worker: makes the app installable and shows a friendly page when offline.
   It never stores account data, documents or API responses. */
const CACHE = 'bizkipe-shell-v1';
const SHELL = ['/offline.html', '/icon-192.png', '/icon-512.png', '/logo.svg'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;          // leave Supabase and other sites alone
  if (url.pathname.startsWith('/api/')) return;             // never touch payments or data calls
  if (req.mode === 'navigate') {
    // Always try the network first so people get the latest pages; only fall back when offline.
    e.respondWith(fetch(req).catch(() => caches.match('/offline.html')));
    return;
  }
  if (SHELL.includes(url.pathname)) {
    e.respondWith(caches.match(req).then((hit) => hit || fetch(req)));
  }
});
