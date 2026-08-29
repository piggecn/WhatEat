/* 今天吃点啥 Service Worker：静态资源网络优先 + 缓存回退；API 永不缓存 */
const CACHE = 'whateat-shell-v1';
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', (e) => {
  const u = new URL(e.request.url);
  if (e.request.method !== 'GET' || u.origin !== location.origin || u.pathname.startsWith('/api/') || u.pathname.startsWith('/uploads/')) return;
  e.respondWith(
    fetch(e.request)
      .then((r) => {
        const c = r.clone();
        caches.open(CACHE).then((ca) => ca.put(e.request, c));
        return r;
      })
      .catch(() => caches.match(e.request).then((m) => m || caches.match('/')))
  );
});
