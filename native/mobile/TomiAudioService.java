package com.tomi.tomi_app;

import android.app.*;
import android.content.*;
import android.content.pm.ServiceInfo;
import android.os.*;

public class TomiAudioService extends Service {
    private static TomiAudioService running;
    private final Handler handler=new Handler(Looper.getMainLooper());
    private String id;
    private boolean microphone;
    private long renewed;
    private PowerManager.WakeLock wake;
    private static final java.util.Map<String,io.flutter.plugin.common.MethodChannel.Result> pending=new java.util.HashMap<>();
    public static boolean active() { return running != null || !pending.isEmpty(); }
    public static void start(Context context,Intent intent,io.flutter.plugin.common.MethodChannel.Result callback) {
        String key=intent.getStringExtra("id");
        if (pending.containsKey(key)) { callback.success(false);return; }
        pending.put(key,callback);
        try {
            if (Build.VERSION.SDK_INT>=26) context.startForegroundService(intent);else context.startService(intent);
        } catch (RuntimeException e) { pending.remove(key);callback.success(false);return; }
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            if (pending.get(key)==callback) { pending.remove(key);stop(context,key);callback.success(false); }
        },5000);
    }
    private static void complete(String key,boolean ok) {
        io.flutter.plugin.common.MethodChannel.Result callback=pending.remove(key);
        if (callback!=null) callback.success(ok);
    }
    private final Runnable watchdog=new Runnable() {
        @Override public void run() {
            if (SystemClock.elapsedRealtime()-renewed>40000) { stopSelf(); return; }
            handler.postDelayed(this,5000);
        }
    };
    public static boolean renew(String id) {
        if (running != null && running.id != null && running.id.equals(id)) {
            running.renewed=SystemClock.elapsedRealtime();
            if (running.wake != null) running.wake.acquire(45000);
            return true;
        }
        return false;
    }
    public static void stop(Context context,String id) {
        io.flutter.plugin.common.MethodChannel.Result callback=pending.remove(id);
        if (callback!=null) callback.success(false);
        if (running != null && running.id != null && running.id.equals(id)) running.stopSelf();
    }
    @Override public void onCreate() { super.onCreate(); running=this; }
    @Override public int onStartCommand(Intent intent,int flags,int startId) {
        if (intent == null || intent.getStringExtra("id") == null) { stopSelf();return START_NOT_STICKY; }
        String next=intent.getStringExtra("id");
        // A cancelled delayed start must never resurrect an old session.
        if (!pending.containsKey(next)) { if (id==null) stopSelf();return START_NOT_STICKY; }
        if (!next.equals(id)) microphone=false;
        id=next; microphone=microphone || intent.getBooleanExtra("microphone",false);
        String kind=intent.getStringExtra("kind");
        TomiCallNotifications.channels(this);
        Intent open=new Intent(this,MainActivity.class).setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP|Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent content=PendingIntent.getActivity(this,900,open,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
        android.content.SharedPreferences prefs=getSharedPreferences("tomi.mobile",0);
        PendingIntent end=TomiCallNotifications.action(this,id,prefs.getString("accountId",""),prefs.getString("bindingId",""),"room".equals(kind)?"leave":"end");
        Notification.Builder b=Build.VERSION.SDK_INT>=26?new Notification.Builder(this,"tomi_audio"):new Notification.Builder(this);
        Notification notification=b.setSmallIcon(R.drawable.tomi_notification).setContentTitle("TOMI")
            .setContentText("room".equals(kind)?"أنت داخل غرفة صوتية":"المكالمة مستمرة")
            .setContentIntent(content).setOngoing(true).setCategory(Notification.CATEGORY_CALL)
            .setVisibility(Notification.VISIBILITY_PRIVATE).addAction(new Notification.Action.Builder(null,"إنهاء",end).build()).build();
        try {
            if (Build.VERSION.SDK_INT>=30) startForeground(900,notification,ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK | (microphone?ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE:0));
            else if (Build.VERSION.SDK_INT>=29) startForeground(900,notification,ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK);
            else startForeground(900,notification);
            if (wake == null) {
                wake=((PowerManager)getSystemService(POWER_SERVICE)).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,"TOMI:Audio");wake.setReferenceCounted(false);
            }
            renew(id); handler.removeCallbacks(watchdog);handler.postDelayed(watchdog,5000);complete(id,true);
        } catch (RuntimeException e) { complete(id,false);stopSelf(); }
        return START_NOT_STICKY;
    }
    @Override public void onDestroy() {
        handler.removeCallbacksAndMessages(null);
        if (wake != null && wake.isHeld()) wake.release();
        stopForeground(true); if (running==this) running=null;super.onDestroy();
        java.util.Map<String,Object> event=new java.util.HashMap<>();event.put("type","audioStopped");event.put("callId",id);MainActivity.dispatch(event);
    }
    @Override public IBinder onBind(Intent intent) { return null; }
}
