package com.tomi.tomi_app;

import android.app.*;
import android.content.*;
import android.os.Build;
import java.util.Map;
import org.json.JSONObject;

/** Generic foreground alerts only; message text and media never enter an alert. */
public final class TomiUpdateNotifications {
    static void channels(Context context) {
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel channel = new NotificationChannel("tomi_updates", "رسائل وتفاعلات TOMI", NotificationManager.IMPORTANCE_HIGH);
            channel.setLockscreenVisibility(Notification.VISIBILITY_PRIVATE);
            channel.enableVibration(true);
            context.getSystemService(NotificationManager.class).createNotificationChannel(channel);
        }
    }
    static void show(Context context, Map<String,String> data) {
        String account=data.get("accountId"),type=data.get("type");
        android.content.SharedPreferences prefs=context.getSharedPreferences("tomi.mobile",0);
        String id="chat".equals(type)?data.get("conversationId"):"activity".equals(type)?data.get("activityId"):"notice".equals(type)?data.get("noticeId"):null;
        if(!MobilePolicy.update(prefs.getBoolean("enabled",false),account,prefs.getString("accountId",null),type,id)) return;
        channels(context);
        android.content.SharedPreferences actions=context.getSharedPreferences("tomi.actions",0);
        String secret=actions.getString("secret",null);
        if(secret==null){secret=java.util.UUID.randomUUID().toString();actions.edit().putString("secret",secret).commit();}
        Intent intent=new Intent(context,MainActivity.class).setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP|Intent.FLAG_ACTIVITY_CLEAR_TOP)
          .setData(android.net.Uri.parse("tomi://notification/"+type+"/"+id)).putExtra("tomiNotification",new JSONObject(data).toString()).putExtra("tomiNonce",secret);
        PendingIntent open=PendingIntent.getActivity(context,0,intent,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
        Notification.Builder builder=Build.VERSION.SDK_INT>=26?new Notification.Builder(context,"tomi_updates"):new Notification.Builder(context);
        builder.setSmallIcon(R.drawable.tomi_notification).setContentTitle("TOMI")
          .setContentText("chat".equals(type)?"وصلتك رسالة جديدة في TOMI":"عندك تنبيه جديد في TOMI")
          .setContentIntent(open).setAutoCancel(true).setVisibility(Notification.VISIBILITY_PRIVATE).setPriority(Notification.PRIORITY_HIGH);
        try {context.getSystemService(NotificationManager.class).notify("update-"+id,902,builder.build());}catch(SecurityException ignored){}
    }
}
