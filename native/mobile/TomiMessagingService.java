package com.tomi.tomi_app;

import com.google.firebase.messaging.RemoteMessage;

// FlutterFire's receiver still supplies onMessage/onMessageOpenedApp. The
// higher-priority service handles data-only call presentation natively, even
// before any Flutter activity exists. Inherited onNewToken is retained.
public class TomiMessagingService extends io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService {
    @Override public void onMessageReceived(RemoteMessage message) {
        TomiCallNotifications.receive(this,message.getData());
        super.onMessageReceived(message);
    }
}
