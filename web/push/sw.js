// Service worker dedicato al Web Push (scope: push/). Convive con quello di Flutter.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

self.addEventListener('push', (event) => {
  let d = {};
  try { d = event.data ? event.data.json() : {}; } catch (_) { d = { body: event.data && event.data.text() }; }
  event.waitUntil(self.registration.showNotification(d.title || 'Corsi SMAM', {
    body: d.body || '',
    tag: d.tag || undefined,
    icon: new URL('../icons/Icon-192.png', self.registration.scope).href,
    badge: new URL('../icons/Icon-192.png', self.registration.scope).href,
  }));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const root = new URL('../', self.registration.scope).href;
  event.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
    for (const c of list) if (c.url.startsWith(root) && 'focus' in c) return c.focus();
    return self.clients.openWindow(root);
  }));
});
