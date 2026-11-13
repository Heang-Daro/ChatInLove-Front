self.addEventListener('push', (event) => {
  const fallbackTitle = 'In Love';
  const fallbackBody = 'You have a new message';

  let data = { title: fallbackTitle, body: fallbackBody };
  try {
    if (event.data) {
      data = event.data.json();
    }
  } catch (_) {
    // Ignore invalid push payloads.
  }

  const options = {
    body: data.body || fallbackBody,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: 'in-love-chat',
    renotify: true,
  };

  event.waitUntil(
    self.registration.showNotification(data.title || fallbackTitle, options)
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = '/';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if (client.url.includes(location.origin) && 'focus' in client) {
          return client.focus();
        }
      }
      return clients.openWindow(url);
    })
  );
});
