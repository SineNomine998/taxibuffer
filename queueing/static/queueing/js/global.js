/**
 * Global TaxiBuffer JavaScript
 * Handles push notifications and GPS tracking across all pages
 */

(function() {
    'use strict';

    const DEBUG = false;

    // Global state
    let entryUuid = null;
    let vapidKey = null;
    let isInQueue = false;
    let gpsInterval = null;
    let watchId = null;

    /**
     * Initialize the global notification handler
     */
    function initGlobalHandler() {
        // Get configuration from page context
        entryUuid = window.TAXIBUFFER_ENTRY_UUID || null;
        vapidKey = window.TAXIBUFFER_VAPID_KEY || null;
        isInQueue = window.TAXIBUFFER_IN_QUEUE || false;

        if (DEBUG) console.log('[Global] Initializing with entryUuid:', entryUuid, 'isInQueue:', isInQueue);

        // Set up Service Worker message listener
        if ('serviceWorker' in navigator) {
            navigator.serviceWorker.addEventListener('message', handleServiceWorkerMessage);
        }

        // Start GPS tracking if user is in queue
        if (isInQueue && entryUuid) {
            startGpsTracking();
        }

        // Try to register service worker for push notifications
        registerServiceWorker();

        navigator.serviceWorker.addEventListener('message', (event) => {
            // existing REFRESH_STATUS handler
            if (event.data?.type === 'REFRESH_STATUS') {
                showNotificationPopup(event.data.data);
                return;
            }
            
            // NEW: SW is asking us to send location
            if (event.data?.type === 'SEND_LOCATION') {
                const uuid = event.data.entry_uuid;
                navigator.geolocation.getCurrentPosition(
                    async (pos) => {
                        await fetch(
                            `/queueing/api/queue/${uuid}/location/` +
                            `?lat=${pos.coords.latitude}&lng=${pos.coords.longitude}`,
                            { method: 'POST', headers: { 'X-CSRFToken': getCsrfToken() } }
                        );
                    },
                    () => {
                        // GPS denied or failed, report without coordinates
                        fetch(`/queueing/api/queue/${uuid}/location/`, { method: 'POST' });
                    },
                    { enableHighAccuracy: true, timeout: 8000, maximumAge: 0 }
                );
            }
        });
    }

    /**
     * Register Service Worker for push notifications
     */
    async function registerServiceWorker() {
        if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
            if (DEBUG) console.log('[Global] Push not supported');
            return;
        }

        try {
            const reg = await navigator.serviceWorker.register('/sw.js');
            if (DEBUG) console.log('[Global] Service worker registered:', reg);

            // Request notification permission if not granted
            if (Notification.permission === 'default') {
                await Notification.requestPermission();
            }

            // Subscribe to push if we have a vapid key and entry uuid
            if (vapidKey && entryUuid) {
                await subscribeToPush(reg);
            }
        } catch (e) {
            if (DEBUG) console.error('[Global] Service worker registration failed:', e);
        }
    }

    /**
     * Subscribe to push notifications
     */
    async function subscribeToPush(registration) {
        try {
            const sub = await registration.pushManager.subscribe({
                userVisibleOnly: true,
                applicationServerKey: urlBase64ToUint8Array(vapidKey)
            });

            // Send subscription to server
            const csrfToken = getCsrfToken();
            await fetch('/queueing/api/push/subscribe/', {
                method: 'POST',
                headers: { 
                    'Content-Type': 'application/json',
                    'X-CSRFToken': csrfToken
                },
                body: JSON.stringify({ subscription: sub, entry_uuid: entryUuid })
            });

            if (DEBUG) console.log('[Global] Subscribed to push');
        } catch (e) {
            if (DEBUG) console.error('[Global] Push subscription failed:', e);
        }
    }

    /**
     * Handle messages from Service Worker
     */
    function handleServiceWorkerMessage(event) {
        if (DEBUG) console.log('[Global] Service worker message:', event.data);

        if (event.data && event.data.type === 'REFRESH_STATUS') {
            const data = event.data.data;
            
            // Show the notification popup
            showNotificationPopup(data);
        }
    }

    /**
     * Show the "Begrepen" notification popup
     * This is the same popup as in queue_status.js
     */
    function showNotificationPopup(data) {
        // Check if Swal (SweetAlert2) is available
        if (typeof Swal === 'undefined') {
            if (DEBUG) console.log('[Global] Swal not available, showing native notification');
            // Fall back to native notification
            if (Notification.permission === 'granted') {
                new Notification(data.title || 'U bent aan de beurt', {
                    body: data.body || 'Ga naar ophaalzone',
                    icon: '/static/queueing/assets/logo.svg'
                });
            }
            return;
        }

        Swal.fire({
            title: data.title || `U mag doorrijden\n#${data.sequence_number || '--'}`,
            html: `
                <div style="text-align: center; margin-bottom: 15px;">
                    <div>
                    <img src="/static/queueing/assets/pop-up-confirmed.svg" 
                        alt="Confirmed" 
                        style="max-width:80px;max-height:80px;width:100%;height:auto;">
                    </div>
                    <div style="font-size: 16px; margin-top: 10px; color: #333;">${data.body || 'Ga naar ophaalzone'}</div>
                </div>
            `,
            showCancelButton: false,
            confirmButtonText: 'Begrepen',
            confirmButtonColor: '#E0BD22',
            backdrop: true,
            allowOutsideClick: false,
            customClass: {
                popup: 'notification-popup',
                confirmButton: 'notification-accept-btn',
                cancelButton: 'notification-decline-btn'
            }
        }).then((result) => {
            if (result.isConfirmed) {
                respondToNotification('accepted').then(() => {
                    if (DEBUG) console.log('[Global] Notification accepted, redirecting...');
                    window.location.href = '/queueing/locations/';
                }).catch(err => {
                    if (DEBUG) console.error('[Global] Failed to respond:', err);
                    window.location.href = '/queueing/locations/';
                });
            } else {
                respondToNotification('declined');
            }
        });
    }

    /**
     * Respond to a notification (accept/decline)
     */
    async function respondToNotification(response) {
        if (!entryUuid) {
            if (DEBUG) console.log('[Global] No entryUuid, cannot respond to notification');
            return;
        }

        const csrfToken = getCsrfToken();
        
        try {
            const res = await fetch('/queueing/api/notification/respond/', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRFToken': csrfToken
                },
                body: JSON.stringify({
                    entry_uuid: entryUuid,
                    response: response
                })
            });

            const data = await res.json();
            if (DEBUG) console.log('[Global] Notification response:', data);
            return data;
        } catch (e) {
            if (DEBUG) console.error('[Global] Failed to respond to notification:', e);
            throw e;
        }
    }

    /**
     * Start GPS tracking for automatic dequeueing
     */
    function startGpsTracking() {
        if (watchId !== null) navigator.geolocation.clearWatch(watchId);

        watchId = navigator.geolocation.watchPosition(
            async (position) => {
                await checkLocationAgainstBuffer({
                    lat: position.coords.latitude,
                    lng: position.coords.longitude
                });
            },
            (err) => { if (DEBUG) console.warn('[Global] watchPosition error:', err); },
            { enableHighAccuracy: true, maximumAge: 15000, timeout: 20000 }
        );

        // Also fire a check when the tab becomes visible again
        document.addEventListener('visibilitychange', () => {
            if (document.visibilityState === 'visible') sendGpsLocation();
        });
    }

    /**
     * Send GPS location to server for automatic dequeueing
     */
    async function sendGpsLocation() {
        if (!entryUuid || !navigator.geolocation) {
            return;
        }

        try {
            const position = await getCurrentPosition();
            if (!position) return;

            const csrfToken = getCsrfToken();
            const endpoint = `/queueing/api/queue/${entryUuid}/status/?lat=${position.lat}&lng=${position.lng}`;

            const res = await fetch(endpoint, {
                method: 'GET',
                headers: { 'Accept': 'application/json' },
                cache: 'no-store'
            });

            const data = await res.json();
            
            if (DEBUG) console.log('[Global] GPS update response:', data);

            // Check if user was auto-dequeued
            if (data.status_code?.toLowerCase() === 'left_zone') {
                // Show alert and redirect
                if (typeof Swal !== 'undefined') {
                    Swal.fire({
                        title: 'U bent buiten de bufferzone',
                        text: 'U bent uit de wachtrij gehaald.',
                        icon: 'warning',
                        confirmButtonText: 'OK'
                    }).then(() => {
                        window.location.href = '/queueing/locations/';
                    });
                } else {
                    alert('U bent buiten de bufferzone en uit de wachtrij gehaald.');
                    window.location.href = '/queueing/locations/';
                }
            }

            let notificationPopupShown = false;

            // Check if there's a pending notification
            if (data.has_notification && !notificationPopupShown) {
                notificationPopupShown = true;
                showNotificationPopup({
                    title: 'U bent aan de beurt',
                    body: 'Ga naar ophaalzone',
                    sequence_number: data.sequence_number
                });
            }

        } catch (e) {
            if (DEBUG) console.error('[Global] GPS update failed:', e);
        }
    }

    /**
     * Get current GPS position
     */
    function getCurrentPosition() {
        return new Promise((resolve) => {
            if (!navigator.geolocation) {
                resolve(null);
                return;
            }

            navigator.geolocation.getCurrentPosition(
                (position) => {
                    resolve({
                        lat: position.coords.latitude,
                        lng: position.coords.longitude
                    });
                },
                (error) => {
                    if (DEBUG) console.warn('[Global] Geolocation error:', error);
                    resolve(null);
                },
                {
                    enableHighAccuracy: true,
                    timeout: 10000,
                    maximumAge: 30000
                }
            );
        });
    }

    /**
     * Convert VAPID key from base64 to Uint8Array
     */
    function urlBase64ToUint8Array(base64String) {
        const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
        const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
        const rawData = window.atob(base64);
        const outputArray = new Uint8Array(rawData.length);
        for (let i = 0; i < rawData.length; ++i) {
            outputArray[i] = rawData.charCodeAt(i);
        }
        return outputArray;
    }

    /**
     * Get CSRF token from cookies
     */
    function getCsrfToken() {
        const c = document.cookie.split(';').find(x => x.trim().startsWith('csrftoken='));
        return c ? decodeURIComponent(c.split('=')[1]) : '';
    }

    // Initialize when DOM is ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initGlobalHandler);
    } else {
        initGlobalHandler();
    }

})();