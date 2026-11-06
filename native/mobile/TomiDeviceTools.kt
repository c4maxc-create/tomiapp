package com.tomi.tomi_app

import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.view.WindowManager

object TomiDeviceTools {
    @JvmStatic fun restore(activity: Activity) {
        if (activity.getSharedPreferences("tomi.privacy",0).getBoolean("secureScreen",false))
            activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
    @JvmStatic fun privacy(activity: Activity, enabled: Boolean) {
        activity.getSharedPreferences("tomi.privacy",0).edit().putBoolean("secureScreen",enabled).apply()
        if (enabled) activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        else activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
    @JvmStatic fun inspect(activity: Activity): Map<String, Boolean> = mapOf(
        "microphone" to (activity.checkSelfPermission("android.permission.RECORD_AUDIO") == PackageManager.PERMISSION_GRANTED),
        "camera" to (activity.checkSelfPermission("android.permission.CAMERA") == PackageManager.PERMISSION_GRANTED),
        "notifications" to ((Build.VERSION.SDK_INT < 33 || activity.checkSelfPermission("android.permission.POST_NOTIFICATIONS") == PackageManager.PERMISSION_GRANTED) && (Build.VERSION.SDK_INT < 24 || activity.getSystemService(android.app.NotificationManager::class.java).areNotificationsEnabled()))
    )
}
