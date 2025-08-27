// Clean, elegant queue management system
class QueueManager {
    constructor(config) {
        // Configuration passed from Django template
        this.config = {
            entryUuid: config.entryUuid,
            notificationTimeoutMinutes: config.notificationTimeoutMinutes || 2,
            updateInterval: 30000, // 30 seconds
            retryDelay: 5000 // 5 seconds on error
        };

        // State management
        this.state = {
            currentNotificationId: null,
            countdownInterval: null,
            updateInterval: null,
            isConnected: false,
            retryCount: 0
        };

        // API endpoints
        this.endpoints = {
            status: `/queueing/api/queue/${this.config.entryUuid}/status/`,
            respond: `/queueing/api/notification/respond/`
        };

        this.init();
    }

    init() {
        console.log('🚕 Queue Manager initialized with UUID:', this.config.entryUuid);
        this.updateStatus();
        this.startPolling();
    }

    startPolling() {
        if (this.state.updateInterval) {
            clearInterval(this.state.updateInterval);
        }

        this.state.updateInterval = setInterval(() => {
            this.updateStatus();
        }, this.config.updateInterval);
    }

    async updateStatus() {
        try {
            console.log('📡 Fetching status from:', this.endpoints.status);
            const response = await fetch(this.endpoints.status);

            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }

            const data = await response.json();

            if (data.success) {
                this.handleSuccessfulUpdate(data);
            } else {
                throw new Error(data.error || 'Unknown API error');
            }

        } catch (error) {
            this.handleUpdateError(error);
        }
    }

    handleSuccessfulUpdate(data) {
        // Reset error state
        this.state.retryCount = 0;
        this.setConnectionStatus(true);

        // Update UI
        this.updateStatusDisplay(data);
        this.updateStats(data);
        this.handleNotification(data);
        this.updateLastUpdated();

        console.log('✅ Status updated successfully:', data);
    }

    handleUpdateError(error) {
        console.error('❌ Status update failed:', error);
        this.state.retryCount++;
        this.setConnectionStatus(false);

        // Show user-friendly error after multiple failures
        if (this.state.retryCount >= 3) {
            this.showAlert('error', 'Connection issues. Retrying...');
        }

        // Exponential backoff for retries
        const delay = Math.min(this.config.retryDelay * this.state.retryCount, 30000);
        setTimeout(() => this.updateStatus(), delay);
    }

    updateStatusDisplay(data) {
        const statusCard = document.getElementById('status-card');
        const statusDisplay = document.getElementById('status-display');

        if (!statusCard || !statusDisplay) {
            console.warn('Status elements not found');
            return;
        }

        // Remove all status classes
        statusCard.classList.remove('status-waiting', 'status-notified', 'status-dequeued');

        // Add appropriate class based on status
        if (data.status_code) {
            statusCard.classList.add(`status-${data.status_code.toLowerCase()}`);
        }

        statusDisplay.innerHTML = `<h4>${data.status || 'Unknown'}</h4>`;
    }

    updateStats(data) {
        this.updateElement('position-display', data.position || 'N/A');
        this.updateElement('total-waiting', data.total_waiting || '0');
        this.updateElement('status-text', (data.status_code || 'unknown').toUpperCase());
    }

    updateElement(id, value) {
        const element = document.getElementById(id);
        if (element) {
            element.textContent = value;
        }
    }

    handleNotification(data) {
        const hasActiveNotification = data.has_notification &&
            data.notification &&
            !data.notification.is_expired;

        if (hasActiveNotification) {
            this.showNotification(data.notification);
        } else {
            this.hideNotification();
        }
    }

    showNotification(notification) {
        this.state.currentNotificationId = notification.id;

        const panel = document.getElementById('notification-panel');
        if (panel) {
            panel.classList.add('show');
        }

        this.startCountdown(new Date(notification.notification_time));

        // Enable notification buttons
        this.setNotificationButtons(false); // false = enabled

        console.log('🔔 Notification displayed:', notification.id);
    }

    hideNotification() {
        const panel = document.getElementById('notification-panel');
        if (panel) {
            panel.classList.remove('show');
        }

        this.clearCountdown();
        this.state.currentNotificationId = null;
    }

    startCountdown(notificationTime) {
        this.clearCountdown();

        this.state.countdownInterval = setInterval(() => {
            const now = new Date();
            const elapsed = Math.floor((now - notificationTime) / 1000);
            const totalSeconds = this.config.notificationTimeoutMinutes * 60;
            const remaining = totalSeconds - elapsed;

            const countdownElement = document.getElementById('countdown-display');

            if (remaining <= 0) {
                if (countdownElement) {
                    countdownElement.textContent = 'Time expired!';
                }
                this.hideNotification();
            } else {
                const minutes = Math.floor(remaining / 60);
                const seconds = remaining % 60;
                if (countdownElement) {
                    countdownElement.textContent =
                        `Time remaining: ${minutes}:${seconds.toString().padStart(2, '0')}`;
                }
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
            this.showAlert('error', 'No active notification to respond to.');
            return;
        }

        // Disable buttons to prevent double-clicking
        this.setNotificationButtons(true);

        try {
            const apiResponse = await fetch(this.endpoints.respond, {
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

            const result = await apiResponse.json();

            if (result.success) {
                this.showAlert('success', result.message);
                this.hideNotification();
                // Force immediate status update
                setTimeout(() => this.updateStatus(), 1000);
            } else {
                throw new Error(result.error || 'Unknown response error');
            }

        } catch (error) {
            console.error('❌ Response failed:', error);
            this.showAlert('error', 'Failed to send response. Please try again.');
            this.setNotificationButtons(false); // Re-enable buttons
        }
    }

    setNotificationButtons(disabled) {
        const acceptBtn = document.getElementById('btn-accept');
        const declineBtn = document.getElementById('btn-decline');

        if (acceptBtn) acceptBtn.disabled = disabled;
        if (declineBtn) declineBtn.disabled = disabled;
    }

    getCSRFToken() {
        const cookies = document.cookie.split(';');
        for (let cookie of cookies) {
            const [name, value] = cookie.trim().split('=');
            if (name === 'csrftoken') {
                return value;
            }
        }
        return '';
    }

    setConnectionStatus(connected) {
        this.state.isConnected = connected;
        const statusElement = document.getElementById('connection-status');

        if (statusElement) {
            if (connected) {
                statusElement.textContent = '🟢 Connected';
                statusElement.className = 'connection-status connected';
            } else {
                statusElement.textContent = '🔴 Disconnected';
                statusElement.className = 'connection-status disconnected';
            }
        }
    }

    updateLastUpdated() {
        const element = document.getElementById('last-updated');
        if (element) {
            element.textContent = `Last updated: ${new Date().toLocaleTimeString()}`;
        }
    }

    showAlert(type, message) {
        const container = document.getElementById('alert-container');
        if (!container) return;

        const alert = document.createElement('div');
        alert.className = `alert alert-${type === 'error' ? 'danger' : type}`;
        alert.textContent = message;

        container.innerHTML = '';
        container.appendChild(alert);

        // Auto-remove after 5 seconds
        setTimeout(() => {
            if (alert.parentNode) {
                alert.parentNode.removeChild(alert);
            }
        }, 5000);
    }

    destroy() {
        // Cleanup intervals
        if (this.state.updateInterval) {
            clearInterval(this.state.updateInterval);
        }
        this.clearCountdown();

        console.log('🚕 Queue Manager destroyed');
    }
}

// Export for module systems or make available globally
if (typeof module !== 'undefined' && module.exports) {
    module.exports = QueueManager;
} else {
    window.QueueManager = QueueManager;
}