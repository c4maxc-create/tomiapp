package com.tomi.tomi_app;

import android.app.*;
import android.content.*;
import android.os.Build;
import android.media.AudioAttributes;
import android.media.RingtoneManager;
import java.util.Map;

public final class TomiCallNotifications {
    public static boolean visible=false;
    private static final String UUID="^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$";
    static void channels(Context c) {
        if (Build.VERSION.SDK_INT<26) return;
        NotificationManager manager=c.getSystemService(NotificationManager.class);
        NotificationChannel ring=new NotificationChannel("tomi_calls","مكالمات TOMI",NotificationManager.IMPORTANCE_HIGH);
        ring.setLockscreenVisibility(Notification.VISIBILITY_PRIVATE);ring.enableVibration(true);
        ring.setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE).build());
        manager.createNotificationChannel(ring);
        manager.createNotificationChannel(new NotificationChannel("tomi_audio","الصوت المستمر",NotificationManager.IMPORTANCE_LOW));
    }
    static void bind(Context c,String account,String binding,boolean enabled) {
        SharedPreferences p=c.getSharedPreferences("tomi.mobile",0);
        if (!java.util.Objects.equals(account,p.getString("accountId",null)) || !java.util.Objects.equals(binding,p.getString("bindingId",null)) || !enabled) {
            for (String k:p.getAll().keySet()) if (k.startsWith("ring:")) c.getSystemService(NotificationManager.class).cancel(k.substring(5),901);
            p.edit().clear().apply();
        }
        p.edit().putString("accountId",account).putString("bindingId",binding).putBoolean("enabled",enabled).apply();
    }
    static PendingIntent action(Context c,String id,String account,String binding,String action) {
        SharedPreferences auth=c.getSharedPreferences("tomi.actions",0);
        String nonce=auth.getString("secret",null);
        if (nonce==null) { nonce=java.util.UUID.randomUUID().toString();auth.edit().putString("secret",nonce).commit(); }
        boolean control="end".equals(action)||"leave".equals(action);
        Intent intent=new Intent(c,control?TomiActionReceiver.class:MainActivity.class).setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP|Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .setData(android.net.Uri.parse("tomi://call/"+id+"/"+action))
            .putExtra("tomiAction",action).putExtra("callId",id).putExtra("accountId",account).putExtra("bindingId",binding).putExtra("tomiNonce",nonce);
        if (control) return PendingIntent.getBroadcast(c,0,intent,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
        return PendingIntent.getActivity(c,0,intent,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
    }
    static void clear(Context c,String id) {
        if (id == null || !id.matches(UUID)) return;
        c.getSystemService(NotificationManager.class).cancel(id,901);
        c.getSystemService(NotificationManager.class).cancel("call-"+id,0);
        c.getSharedPreferences("tomi.mobile",0).edit().putLong("closed:"+id,System.currentTimeMillis()+120000).remove("ring:"+id).apply();
    }
    static void receive(Context c,Map<String,String> data) {
        String type=data.get("type"),id=data.get("callId"),account=data.get("accountId"),binding=data.get("bindingId");
        if (id == null || !id.matches(UUID) || !("call".equals(type)||"call_cancel".equals(type))) return;
        SharedPreferences prefs=c.getSharedPreferences("tomi.mobile",0);
        if (account == null || binding == null || !account.equals(prefs.getString("accountId",null)) || !binding.equals(prefs.getString("bindingId",null))) return;
        if ("call_cancel".equals(type)) { clear(c,id);return; }
        long now=System.currentTimeMillis(),expires;
        try { expires=Long.parseLong(data.get("expiresAt")); } catch (Exception e) { return; }
        if (!MobilePolicy.incoming(now,expires,prefs.getLong("closed:"+id,0),prefs.getBoolean("enabled",false),account,binding,prefs.getString("accountId",null),prefs.getString("bindingId",null))) return;
        // Periodically prune receipts without reviving an ended ring.
        SharedPreferences.Editor edit=prefs.edit();
        for (Map.Entry<String,?> e:prefs.getAll().entrySet()) if ((e.getKey().startsWith("closed:")||e.getKey().startsWith("ring:")) && e.getValue() instanceof Long && (Long)e.getValue()<now) edit.remove(e.getKey());
        edit.putLong("ring:"+id,expires).apply();channels(c);
        PendingIntent answer=action(c,id,account,binding,"answer"),decline=action(c,id,account,binding,"decline"),open=action(c,id,account,binding,"open");
        Notification.Builder b=Build.VERSION.SDK_INT>=26?new Notification.Builder(c,"tomi_calls"):new Notification.Builder(c);
        b.setSmallIcon(R.drawable.tomi_notification).setContentTitle("TOMI").setContentText("video".equals(data.get("kind"))?"مكالمة فيديو واردة":"مكالمة صوتية واردة")
            .setCategory(Notification.CATEGORY_CALL).setPriority(Notification.PRIORITY_MAX).setVisibility(Notification.VISIBILITY_PRIVATE)
            .setContentIntent(open).setOnlyAlertOnce(true).setAutoCancel(true);
        if (Build.VERSION.SDK_INT>=26) b.setTimeoutAfter(Math.max(1,expires-now));
        if (Build.VERSION.SDK_INT>=31) b.setStyle(Notification.CallStyle.forIncomingCall(new Person.Builder().setName("TOMI").setImportant(true).build(),decline,answer).setIsVideo("video".equals(data.get("kind"))));
        else b.addAction(new Notification.Action.Builder(null,"رفض",decline).build()).addAction(new Notification.Action.Builder(null,"رد",answer).build());
        try {
            Notification incoming=b.build();incoming.flags|=Notification.FLAG_INSISTENT;
            c.getSystemService(NotificationManager.class).notify(id,901,incoming);
            if (Build.VERSION.SDK_INT<26) {
                Intent expire=new Intent(c,TomiRingExpiryReceiver.class).setData(android.net.Uri.parse("tomi://expire/"+id)).putExtra("callId",id);
                PendingIntent pending=PendingIntent.getBroadcast(c,0,expire,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
                c.getSystemService(AlarmManager.class).setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP,android.os.SystemClock.elapsedRealtime()+expires-now,pending);
            }
        } catch (SecurityException ignored) { }
    }
}
