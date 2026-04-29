const DEBUG = false;

self.addEventListener('push', (event) => {
  if (DEBUG) console.log('[Service Worker] Push received:', event);

  if (!event.data) {
    console.warn('[Service Worker] Push event but no data');
    return;
  }

  try {
    const data = event.data.json();
    if (DEBUG) console.log('[Service Worker] Push data:', data);

    if (data.type === 'LOCATION_PING') {
        event.waitUntil(handleLocationPing(data));
        return; // do NOT show a notification
    }

    let title = data.title || 'TaxiBuffer Bericht';

    const options = {
      body: data.body || `U mag doorrijden\n#${data.sequence_number || '--'}`,
      icon: '/static/queueing/assets/logo.svg',
      badge: '/static/queueing/assets/check-badge.svg',
      vibrate: [200, 100, 200, 100, 200], // dunno how this feels like on a phone
      tag: data.tag || 'taxibuffer-notification',
      requireInteraction: true,
      data: {
        ...data.data,
      },
      actions: [
        {
          action: 'open',
          title: 'Open App'
        }
      ]
    };

    if (DEBUG) console.log('[Service Worker] Showing notification with options:', options);

    event.waitUntil(
      self.registration.showNotification(title, options)
        .then(() => {
          if (DEBUG) console.log('[Service Worker] Notification shown successfully');

          // Send message to any open clients
          return self.clients.matchAll({ type: 'window' }).then(clients => {
            if (clients && clients.length) {
              for (let client of clients) {
                client.postMessage({
                  type: 'REFRESH_STATUS',
                  data: {
                    ...data,
                  },
                  options: options,
                  timestamp: Date.now()
                });
              }
            }
          });
        })
    );
  } catch (err) {
    console.error('[Service Worker] Error processing push event:', err);
  }
});

self.addEventListener('notificationclick', (event) => {
  if (DEBUG) console.log('[Service Worker] Notification clicked:', event);

  event.notification.close();

  // Get the URL from notification data or use default
  const urlToOpen = event.notification.data?.url || '/queueing/queue/';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then((clientList) => {
        // If there's already a window open, focus it and navigate to the URL
        for (const client of clientList) {
          if (client.url.includes(self.location.origin) && 'focus' in client) {
            client.navigate(urlToOpen);
            return client.focus();
          }
        }
        // Otherwise, open a new window
        if (clients.openWindow) {
          return clients.openWindow(urlToOpen);
        }
      })
  );
});

async function handleLocationPing(data) {
    const entryUuid = data.entry_uuid;
    if (!entryUuid) return;

    try {
        // Service Workers can use the Geolocation API via a client window
        // They cannot call navigator.geolocation directly, so we ask a client to do it
        const clients = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });

        if (clients.length > 0) {
            // There's an open window/tab, ask it to send location
            clients[0].postMessage({ type: 'SEND_LOCATION', entry_uuid: entryUuid });
        } else {
            // No open client, report to server without location
            // Server will treat absence of GPS as "unknown", not dequeue
            await reportLocationToServer(entryUuid, null, null);
        }
    } catch (e) {
        console.error('[SW] Location ping failed:', e);
    }
}

async function reportLocationToServer(entryUuid, lat, lng) {
    let url = `/queueing/api/queue/${entryUuid}/location/`;
    if (lat !== null && lng !== null) {
        url += `?lat=${lat}&lng=${lng}`;
    }
    
    try {
        await fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            // No CSRF needed if you exempt this endpoint, or pass token via URL param
        });
    } catch (e) {
        console.error('[SW] Failed to report location:', e);
    }
}
