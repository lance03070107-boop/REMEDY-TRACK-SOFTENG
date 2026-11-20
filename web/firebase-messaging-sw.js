// Firebase Cloud Messaging background Service Worker for RemedyTrack Web.
// Loaded by firebase_messaging when registering web push notifications.
self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('push', (event) => {
  if (!event.data) return;
  try {
    const payload = event.data.json();
    const notification = payload.notification || {};
    const title = notification.title || 'RemedyTrack Alert';
    const options = {
      body: notification.body || 'You have a medication update.',
      icon: '/icons/Icon-192.png',
      badge: '/icons/Icon-192.png',
      data: payload.data || {},
    };
    event.waitUntil(self.registration.showNotification(title, options));
  } catch (_) {}
});
