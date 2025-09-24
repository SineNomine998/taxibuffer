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

async function registerSWAndSubscribe(vapidPublicKey, entryUuid) {
    if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
        console.warn('Push not supported in this browser');
        return null;
    }

    console.log('Requesting notification permission...');
    const permission = await Notification.requestPermission();
    console.log('Notification permission response:', permission);

    if (permission !== 'granted') {
        console.warn('Notification permission not granted');
        alert('Please enable notifications to receive updates when it\'s your turn');
        return null;
    }

    try {
        const reg = await navigator.serviceWorker.register('/sw.js');
        console.log('Service worker registered', reg);

        const permission = await Notification.requestPermission();
        if (permission !== 'granted') {
            console.warn('Notification permission not granted');
            return null;
        }

        const sub = await reg.pushManager.subscribe({
            userVisibleOnly: true,
            applicationServerKey: urlBase64ToUint8Array(vapidPublicKey)
        });

        await fetch('/queueing/api/push/subscribe/', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRFToken': (function () { const c = document.cookie.split(';').find(x => x.trim().startsWith('csrftoken=')); return c ? decodeURIComponent(c.split('=')[1]) : '' })() },
            body: JSON.stringify({ subscription: sub, entry_uuid: entryUuid })
        });

        console.log('Subscribed to push');
        return sub;
    } catch (e) {
        console.error('subscribe failed', e);
        return null;
    }
}


class QueueManager {
    constructor(config) {
        this.config = {
            entryUuid: config.entryUuid,
            notificationTimeoutMinutes: config.notificationTimeoutMinutes || 2,
            updateInterval: 30000, // 30 seconds
            endpoints: {
                status: `/queueing/api/queue/${config.entryUuid}/status/`,
                respond: `/queueing/api/notification/respond/`
            }
        };

        this.state = {
            currentNotificationId: null,
            countdownInterval: null,
            pollTimer: null,
            alignmentTimeout: null,
            isConnected: false,
            retryCount: 0,
            initialUpdateDone: false // track inital update
        };

        this.init(true);

        this.setupServiceWorkerMessageListener();
    }

    setupServiceWorkerMessageListener() {
        navigator.serviceWorker.addEventListener('message', (event) => {
            console.log('Received message from service worker:', event.data);

            if (event.data && event.data.type === 'REFRESH_STATUS') {
                // Force immediate status update
                console.log('Received push notification, updating status immediately');
                this.updateStatus('push_notification');

                // if (event.data.data) {
                //     const notificationData = {
                //         title: "U mag doorrijden",
                //         body: "Ga naar de ophaalzone."
                //     };
                //     this.showPushReceivedFeedback(notificationData);
                // }
            }
        });
    }

    showPushReceivedFeedback(data) {
        Swal.fire({
            title: data.title || 'U mag doorrijden',
            html: `
        <div style="text-align: center; margin-bottom: 15px;">
            <div>
            <img src="../../../static/queueing/assets/pop-up-confirmed.svg" 
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
                if (this.state.currentNotificationId) {
                    Swal.showLoading();
                    this.respondToNotification('accepted').then(() => {
                        console.log("Successfully responded to notification. Redirecting...")
                        setTimeout(() => {
                            window.location.href = '/queueing/locations/';
                        }, 500)
                    }).catch(err => {
                        console.error('Failed to respond to notification:', err);
                        window.location.href = '/queueing/locations/';
                    });
                } else {
                    window.location.href = '/queueing/locations/';
                }
            } else {
                if (this.state.currentNotificationId) {
                    this.respondToNotification('declined');
                }
            }
        });
    }

    init(immediateUpdate = false) {
        this.setConnectionStatus(false);

        if (immediateUpdate) {
            console.log('Performing immediate update on page load...');
            setTimeout(() => {
                this.updateStatus('initial');
                this.state.initialUpdateDone = true;
            }, 100);
        }

        this.startAlignedPolling();
        console.log('QueueManager initialized, aligned polling started.');

        this.checkAndRepairSubscription();
    }

    // this doesn't seem to work but leaving it in for now
    checkAndRepairSubscription() {
        setTimeout(async () => {
            try {
                if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
                    console.warn('Push not supported in this browser');
                    return;
                }

                // Check if we have a service worker and subscription
                const reg = await navigator.serviceWorker.ready;
                const sub = await reg.pushManager.getSubscription();

                // If no subscription exists, try to resubscribe
                if (!sub) {
                    console.log('No push subscription found, attempting to resubscribe...');
                    const vapidKey = document.querySelector('script[data-vapid-public-key]')?.dataset.vapidKey;
                    if (vapidKey) {
                        await registerSWAndSubscribe(vapidKey, this.config.entryUuid);
                        console.log('Resubscription complete');
                    }
                }
            } catch (e) {
                console.error('Subscription check failed:', e);
            }
        }, 5000); // Check 5 seconds after page load
    }

    startAlignedPolling() {
        if (this.state.alignmentTimeout) {
            clearTimeout(this.state.alignmentTimeout);
            this.state.alignmentTimeout = null;
        }
        if (this.state.pollTimer) {
            clearInterval(this.state.pollTimer);
            this.state.pollTimer = null;
        }

        const calculateNextBoundaryDelay = () => {
            const now = new Date();
            const seconds = now.getSeconds();
            const ms = now.getMilliseconds();

            // Calculate seconds until next :00 or :30 boundary
            const secondsToNext = seconds < 30 ?
                30 - seconds :
                60 - seconds;

            // Calculate total milliseconds until boundary
            return (secondsToNext * 1000) - ms;
        };

        const scheduleFirstUpdate = () => {
            const delay = calculateNextBoundaryDelay();

            console.log(`Scheduling first aligned update in ${delay}ms to align with next :00/:30 boundary`);

            this.updateLastUpdatedLabel(`Next aligned update: ${new Date(Date.now() + delay).toLocaleTimeString()}`);

            this.state.alignmentTimeout = setTimeout(() => {
                const boundaryTime = new Date();
                console.log(`Aligned update at ${boundaryTime.toLocaleTimeString()}`);

                this.updateStatus('aligned');

                this.setupSelfCorrectingInterval();

                this.state.alignmentTimeout = null;
            }, delay);
        };

        // Self-correcting interval that maintains alignment with :00/:30
        this.setupSelfCorrectingInterval = () => {
            if (this.state.pollTimer) clearInterval(this.state.pollTimer);

            this.state.pollTimer = setInterval(() => {
                const now = new Date();
                const seconds = now.getSeconds();
                const ms = now.getMilliseconds();

                const isAtBoundary = (seconds === 0 || seconds === 30) && ms < 100;

                if (isAtBoundary) {
                    this.updateStatus('aligned');
                } else {
                    clearInterval(this.state.pollTimer);
                    scheduleFirstUpdate();
                }
            }, this.config.updateInterval - 100);
        };

        scheduleFirstUpdate();
    }

    async updateStatus(source = 'unknown') {
        try {
            console.log(`Fetching status (source: ${source})...`)
            const response = await fetch(this.config.endpoints.status, {
                method: 'GET',
                headers: { 'Accept': 'application/json' },
                cache: 'no-store'
            });

            if (!response.ok) {
                console.log("NOLUYOR AQ")
                throw new Error(`HTTP ${response.status}`);
            }

            const data = await response.json();
            if (!data.success) {
                throw new Error(data.error || 'API returned unsuccessful');
            }

            this.state.retryCount = 0;
            this.setConnectionStatus(true);

            // Update UI pieces
            this.updateElementsFromData(data);
            this.handleNotification(data);
            this.updateLastUpdated();

        } catch (err) {
            console.error('Update failed:', err);
            this.state.retryCount++;
            this.setConnectionStatus(false);

            // show friendly alert after a few retries
            if (this.state.retryCount >= 3) {
                this.showAlert('error', 'Verbindingsproblemen. Opnieuw proberen...');
            }
        }
    }

    updateElementsFromData(data) {
        const pos = (data.position !== undefined ? data.position : '-');
        const posEl = document.getElementById('position-display');
        if (posEl) posEl.textContent = pos;
    }

    handleNotification(data) {
        const hasActiveNotification = data.has_notification && data.notification && !data.notification.is_expired;
        if (hasActiveNotification) {
            this.state.currentNotificationId = data.notification.id;
            // this.startCountdown(new Date(data.notification.notification_time));

            if (!this.state.shownNotifications) this.state.shownNotifications = {};

            if (!this.state.shownNotifications[data.notification.id]) {
                this.state.shownNotifications[data.notification.id] = true;

                let notificationData = {
                    title: "U mag doorrijden",
                    body: "Rij door naar de ophaallocatie voor de Cruise Terminal. Volg de borden.",
                };

                setTimeout(() => this.showPushReceivedFeedback(notificationData), 500);
            }
        } else {
            this.hideNotification();
        }
    }

    showNotification(notification) {
        this.state.currentNotificationId = notification.id;
        this.showAlert('success', 'U bent nu aan de beurt en mag naar de ophaalzone.');
        // this.startCountdown(new Date(notification.notification_time));
    }

    hideNotification() {
        // this.clearCountdown();
        this.state.currentNotificationId = null;
    }

    // startCountdown(notificationTime) {
    //     this.clearCountdown();
    //     const totalSeconds = this.config.notificationTimeoutMinutes * 60;
    //     const countdownEl = document.getElementById('last-updated');

    //     this.state.countdownInterval = setInterval(() => {
    //         const now = new Date();
    //         const elapsed = Math.floor((now - notificationTime) / 1000);
    //         const remaining = totalSeconds - elapsed;

    //         if (remaining <= 0) {
    //             if (countdownEl) countdownEl.textContent = `Seintje verlopen. Laatste update: ${new Date().toLocaleTimeString()}`;
    //             this.hideNotification();

    //             setTimeout(() => {
    //                 this.updateStatus('timeout');
    //             }, 1000);
    //             return;
    //         }
    //         const minutes = Math.floor(remaining / 60);
    //         const seconds = remaining % 60;
    //         if (countdownEl) {
    //             countdownEl.textContent = `Time remaining: ${minutes}:${String(seconds).padStart(2, '0')}`;
    //         }
    //     }, 1000);
    // }

    // clearCountdown() {
    //     if (this.state.countdownInterval) {
    //         clearInterval(this.state.countdownInterval);
    //         this.state.countdownInterval = null;
    //     }
    // }

    async respondToNotification(response) {
        if (!this.state.currentNotificationId) {
            this.showAlert('error', 'Geen actieve notificatie om te beantwoorden.');
            return Promise.reject('No active notification');
        }

        try {
            const res = await fetch(this.config.endpoints.respond, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRFToken': this.getCSRFToken()
                },
                body: JSON.stringify({
                    notification_id: this.state.currentNotificationId,
                    response: response
                })
            });

            const result = await res.json();
            if (!result.success) throw new Error(result.error || 'Unknown response');

            this.showAlert('success', result.message || 'Respons verzonden');
            this.hideNotification();

            setTimeout(() => this.updateStatus(), 1000);

            return result;

        } catch (err) {
            console.error('Respond failed', err);
            this.showAlert('error', 'Kon reactie niet versturen. Probeer opnieuw.');
            return Promise.reject(err);
        }
    }

    setConnectionStatus(connected) {
        this.state.isConnected = connected;
        const el = document.getElementById('connection-status');
        if (!el) return;
        if (connected) {
            el.textContent = '🟢 Connected';
            el.className = 'connection-status connected';
        } else {
            el.textContent = '🔴 Disconnected';
            el.className = 'connection-status disconnected';
        }
    }

    updateLastUpdated() {
        const el = document.getElementById('last-updated');
        if (el) {
            el.textContent = `Last updated: ${new Date().toLocaleTimeString()}`;
        }
    }

    updateLastUpdatedLabel(text) {
        const el = document.getElementById('last-updated');
        if (el) el.textContent = text;
    }

    showAlert(type, message) {
        const container = document.getElementById('alert-container');
        if (!container) return;

        container.innerHTML = '';
        const div = document.createElement('div');
        div.className = 'alert';
        div.style.padding = '10px';
        div.style.borderRadius = '8px';
        div.style.marginBottom = '8px';
        div.style.fontSize = '13px';

        if (type === 'success') {
            div.style.background = '#d4edda';
            div.style.color = '#155724';
            div.textContent = message;
        } else if (type === 'error') {
            div.style.background = '#f8d7da';
            div.style.color = '#721c24';
            div.textContent = message;
        } else {
            div.style.background = '#fff3cd';
            div.style.color = '#856404';
            div.textContent = message;
        }

        container.appendChild(div);

        setTimeout(() => {
            if (div.parentNode) div.parentNode.removeChild(div);
        }, 5000);
    }

    getCSRFToken() {
        const cookies = document.cookie.split(';');
        for (let c of cookies) {
            const [name, ...v] = c.trim().split('=');
            if (name === 'csrftoken') return decodeURIComponent(v.join('='));
        }
        return '';
    }

    destroy() {
        if (this.state.alignmentTimeout) clearTimeout(this.state.alignmentTimeout);
        if (this.state.pollTimer) clearInterval(this.state.pollTimer);
        // this.clearCountdown();
        console.log('QueueManager destroyed');
    }
}

// cleanup on unload
window.addEventListener('beforeunload', () => {
    if (window.queueManager && typeof window.queueManager.destroy === 'function') {
        window.queueManager.destroy();
    }
});
