// LinkKey Google Messages Notification Interceptor
// This script intercepts web notifications and forwards them to the LinkKey app via WebSocket

(function() {
    'use strict';

    const LINKKEY_PORT = 2847;
    const LINKKEY_WS_URL = `wss://127.0.0.1:${LINKKEY_PORT}`;

    let socket = null;
    let messageQueue = [];
    let reconnectAttempts = 0;
    const MAX_RECONNECT_ATTEMPTS = 5;

    // Connect to LinkKey WebSocket server
    function connect() {
        try {
            socket = new WebSocket(LINKKEY_WS_URL);

            socket.onopen = function() {
                console.log('[LinkKey] WebSocket connected to LinkKey');
                reconnectAttempts = 0;
                // Send any queued messages
                while (messageQueue.length > 0) {
                    const msg = messageQueue.shift();
                    socket.send(msg);
                    console.log('[LinkKey] Sent queued message');
                }
            };

            socket.onclose = function() {
                console.log('[LinkKey] WebSocket disconnected');
                socket = null;
                // Try to reconnect after a delay
                if (reconnectAttempts < MAX_RECONNECT_ATTEMPTS) {
                    reconnectAttempts++;
                    setTimeout(connect, 2000 * reconnectAttempts);
                }
            };

            socket.onerror = function(err) {
                console.log('[LinkKey] WebSocket error:', err);
            };

            socket.onmessage = function(event) {
                console.log('[LinkKey] Received:', event.data);
            };

        } catch (e) {
            console.log('[LinkKey] Failed to create WebSocket:', e);
        }
    }

    // Send notification data to LinkKey
    function sendToLinkKey(title, body) {
        const data = JSON.stringify({
            title: title,
            body: body || '',
            timestamp: Date.now(),
            id: Math.random().toString(36).substring(2, 15)
        });

        if (socket && socket.readyState === WebSocket.OPEN) {
            socket.send(data);
            console.log('[LinkKey] Sent notification via WebSocket');
        } else {
            // Queue the message for when we reconnect
            messageQueue.push(data);
            console.log('[LinkKey] Queued notification, WebSocket not ready');
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
        console.log('[LinkKey] Notification intercepted:', title, options);
        sendToLinkKey(title, options.body);

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
            console.log('[LinkKey] ServiceWorker notification intercepted:', title, options);
            sendToLinkKey(title, options.body);
            return originalShowNotification.call(this, title, options);
        };
    }

    // Initial connection
    connect();

    console.log('[LinkKey] Notification interceptor installed (WebSocket mode)');
})();
