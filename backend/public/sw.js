// Minimal service worker: makes the web app installable. Pages always come from the
// network (no offline cache), so updates show up right away.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', () => {});
