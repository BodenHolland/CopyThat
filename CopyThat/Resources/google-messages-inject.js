// CopyThat Google Messages Notification Interceptor
// This script intercepts web notifications and forwards them to the CopyThat app via WebSocket

(function() {
    'use strict';

    const COPYTHAT_PORT = 2847;
    const COPYTHAT_WS_URL = `wss://127.0.0.1:${COPYTHAT_PORT}`;

    let socket = null;
    let messageQueue = [];
    let reconnectAttempts = 0;
    const MAX_RECONNECT_ATTEMPTS = 5;

    // Connect to CopyThat WebSocket server
    function connect() {
        try {
            socket = new WebSocket(COPYTHAT_WS_URL);

            socket.onopen = function() {
                console.log('[CopyThat] WebSocket connected to CopyThat');
                reconnectAttempts = 0;
                // Send any queued messages
                while (messageQueue.length > 0) {
                    const msg = messageQueue.shift();
                    socket.send(msg);
                    console.log('[CopyThat] Sent queued message');
                }
            };

            socket.onclose = function() {
                console.log('[CopyThat] WebSocket disconnected');
                socket = null;
                // Try to reconnect after a delay
                if (reconnectAttempts < MAX_RECONNECT_ATTEMPTS) {
                    reconnectAttempts++;
                    setTimeout(connect, 2000 * reconnectAttempts);
                }
            };

            socket.onerror = function(err) {
                console.log('[CopyThat] WebSocket error:', err);
            };

            socket.onmessage = function(event) {
                console.log('[CopyThat] Received:', event.data);
            };

        } catch (e) {
            console.log('[CopyThat] Failed to create WebSocket:', e);
        }
    }

    // Send notification data to CopyThat
    function sendToCopyThat(title, body) {
        const data = JSON.stringify({
            title: title,
            body: body || '',
            timestamp: Date.now(),
            id: Math.random().toString(36).substring(2, 15)
        });

        if (socket && socket.readyState === WebSocket.OPEN) {
            socket.send(data);
            console.log('[CopyThat] Sent notification via WebSocket');
        } else {
            // Queue the message for when we reconnect
            messageQueue.push(data);
            console.log('[CopyThat] Queued notification, WebSocket not ready');
            // Try to reconnect if not already trying
            if (!socket || socket.readyState === WebSocket.CLOSED) {
                connect();
            }
        }
    }

    // Store the original Notification constructor
    const OriginalNotification = window.Notification;

    // Override the Notification constructor
    window.Notification = function(title, options = {}) {
        console.log('[CopyThat] Notification intercepted:', title, options);
        sendToCopyThat(title, options.body);

        // Create the original notification so the user still sees it
        return new OriginalNotification(title, options);
    };

    // Copy static properties and methods
    window.Notification.permission = OriginalNotification.permission;
    window.Notification.requestPermission = OriginalNotification.requestPermission.bind(OriginalNotification);
    window.Notification.maxActions = OriginalNotification.maxActions;

    // Also intercept ServiceWorker notifications if available
    if ('serviceWorker' in navigator) {
        const originalShowNotification = ServiceWorkerRegistration.prototype.showNotification;
        ServiceWorkerRegistration.prototype.showNotification = function(title, options = {}) {
            console.log('[CopyThat] ServiceWorker notification intercepted:', title, options);
            sendToCopyThat(title, options.body);
            return originalShowNotification.call(this, title, options);
        };
    }

    // Initial connection
    connect();

    console.log('[CopyThat] Notification interceptor installed (WebSocket mode)');
})();
