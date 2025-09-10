const DEBUG = true;

self.addEventListener('push', (event) => {
  if (DEBUG) console.log('[Service Worker] Push received:', event);

  if (!event.data) {
    console.warn('[Service Worker] Push event but no data');
    return;
  }

  try {
    const data = event.data.json();
    if (DEBUG) console.log('[Service Worker] Push data:', data);

    
    let title = data.title || 'TaxiBuffer Bericht';

    const options = {
      body: data.body || 'U mag doorrijden',
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
