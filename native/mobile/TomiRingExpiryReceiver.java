package com.tomi.tomi_app;

import android.content.*;

/** Android 6/7 fallback; Android 8+ uses Notification.setTimeoutAfter. */
public class TomiRingExpiryReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context c,Intent intent) {
        TomiCallNotifications.clear(c,intent.getStringExtra("callId"));
    }
}
