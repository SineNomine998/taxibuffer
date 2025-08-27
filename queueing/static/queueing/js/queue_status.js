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
            initialUpdateDone: false // Track if initial update has been done
        };

        // init and now DO force an immediate status fetch
        this.init(true); // Pass true to indicate we want an immediate update
    }

    init(immediateUpdate = false) {
        // Set connection as disconnected until we successfully fetch once
        this.setConnectionStatus(false);

        // Perform immediate update if requested
        if (immediateUpdate) {
            console.log('Performing immediate update on page load...');
            // Use a small timeout to ensure DOM is ready
            setTimeout(() => {
                this.updateStatus('initial');
                this.state.initialUpdateDone = true;
            }, 100);
        }

        // Start the aligned polling mechanism (unaffected by immediate update)
        this.startAlignedPolling();
        console.log('QueueManager initialized, aligned polling started.');
    }

    startAlignedPolling() {
        // Clear any existing timers
        if (this.state.alignmentTimeout) {
            clearTimeout(this.state.alignmentTimeout);
            this.state.alignmentTimeout = null;
        }
        if (this.state.pollTimer) {
            clearInterval(this.state.pollTimer);
            this.state.pollTimer = null;
        }

        // Calculate time to next boundary with precision
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

        // Schedule first update to happen exactly at the next :00 or :30
        const scheduleFirstUpdate = () => {
            const delay = calculateNextBoundaryDelay();

            console.log(`Scheduling first aligned update in ${delay}ms to align with next :00/:30 boundary`);

            this.updateLastUpdatedLabel(`Next aligned update: ${new Date(Date.now() + delay).toLocaleTimeString()}`);

            this.state.alignmentTimeout = setTimeout(() => {
                // Execute right at the boundary
                const boundaryTime = new Date();
                console.log(`Aligned update at ${boundaryTime.toLocaleTimeString()}`);

                // Execute update
                this.updateStatus('aligned');

                // Now start the self-correcting interval timer
                this.setupSelfCorrectingInterval();

                this.state.alignmentTimeout = null;
            }, delay);
        };

        // Set up a self-correcting interval that maintains alignment with :00/:30
        this.setupSelfCorrectingInterval = () => {
            // Clear any existing poll timer
            if (this.state.pollTimer) clearInterval(this.state.pollTimer);

            // Use a slightly shorter interval and self-correct
            this.state.pollTimer = setInterval(() => {
                const now = new Date();
                const seconds = now.getSeconds();
                const ms = now.getMilliseconds();

                // Check if we're at a proper boundary (within 100ms tolerance)
                const isAtBoundary = (seconds === 0 || seconds === 30) && ms < 100;

                if (isAtBoundary) {
                    // We're at an exact boundary, make the request
                    console.log(`Aligned update at ${now.toLocaleTimeString()}`);
                    this.updateStatus('aligned');
                } else {
                    // We've drifted, reschedule the whole mechanism
                    console.log(`Detected drift (${seconds}s ${ms}ms), realigning...`);
                    clearInterval(this.state.pollTimer);
                    scheduleFirstUpdate();
                }
            }, this.config.updateInterval - 100); // Slightly shorter interval to detect drift
        };

        // Start the alignment process
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
            // Do not change alignment; let aligned interval continue
        }
    }

    updateElementsFromData(data) {
        // position
        const pos = (data.position !== undefined ? data.position : '-');
        const posEl = document.getElementById('position-display');
        if (posEl) posEl.textContent = pos;

        // any other elements can be updated here
    }

    handleNotification(data) {
        const hasActiveNotification = data.has_notification && data.notification && !data.notification.is_expired;
        if (hasActiveNotification) {
            this.showNotification(data.notification);
        } else {
            this.hideNotification();
        }
    }

    showNotification(notification) {
        this.state.currentNotificationId = notification.id;
        // display countdown etc (you can adapt markup)
        // For this design we choose to show an alert and start countdown in last-updated area
        this.showAlert('success', 'U krijgt nu een seintje. Ga naar ophaalzone als u accepteert.');
        this.startCountdown(new Date(notification.notification_time));
    }

    hideNotification() {
        this.clearCountdown();
        this.state.currentNotificationId = null;
    }

    startCountdown(notificationTime) {
        this.clearCountdown();
        const totalSeconds = this.config.notificationTimeoutMinutes * 60;
        const countdownEl = document.getElementById('last-updated');

        this.state.countdownInterval = setInterval(() => {
            const now = new Date();
            const elapsed = Math.floor((now - notificationTime) / 1000);
            const remaining = totalSeconds - elapsed;

            if (remaining <= 0) {
                if (countdownEl) countdownEl.textContent = `Seintje verlopen. Laatste update: ${new Date().toLocaleTimeString()}`;
                this.hideNotification();
                return;
            }
            const minutes = Math.floor(remaining / 60);
            const seconds = remaining % 60;
            if (countdownEl) {
                countdownEl.textContent = `Time remaining: ${minutes}:${String(seconds).padStart(2, '0')}`;
            }
        }, 1000);
    }

    clearCountdown() {
        if (this.state.countdownInterval) {
            clearInterval(this.state.countdownInterval);
            this.state.countdownInterval = null;
        }
    }

    async respondToNotification(response) {
        if (!this.state.currentNotificationId) {
            this.showAlert('error', 'Geen actieve notificatie om te beantwoorden.');
            return;
        }

        try {
            console.log("YOO")
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

            // Force immediate status fetch at next aligned tick (don't break alignment).
            // Optionally we do a short delayed fetch to reflect change faster without breaking alignment:
            setTimeout(() => this.updateStatus(), 1000);

        } catch (err) {
            console.error('Respond failed', err);
            this.showAlert('error', 'Kon reactie niet versturen. Probeer opnieuw.');
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
        this.clearCountdown();
        console.log('QueueManager destroyed');
    }
}

// cleanup on unload
window.addEventListener('beforeunload', () => {
    if (window.queueManager && typeof window.queueManager.destroy === 'function') {
        window.queueManager.destroy();
    }
});
