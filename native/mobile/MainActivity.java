package com.tomi.tomi_app;

import android.content.Intent;
import android.os.Bundle;
import androidx.annotation.NonNull;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import java.util.HashMap;
import java.util.Map;
import org.json.JSONObject;

public class MainActivity extends FlutterActivity {
    // The foreground service owns lifetime while the UI is detached. Never
    // create another isolate/another media session on activity recreation.
    private static FlutterEngine retained;
    private MethodChannel channel;
    private static MethodChannel events;
    public static void dispatch(Map<String,Object> data) { if (events!=null) events.invokeMethod("action",data); }
    private Intent pendingAudio;
    private MethodChannel.Result pendingAudioResult;
    private boolean waitingForBluetooth;
    @Override public FlutterEngine provideFlutterEngine(@NonNull android.content.Context context) { return retained; }
    @Override public boolean shouldDestroyEngineWithHost() { return false; }
    @Override public void configureFlutterEngine(@NonNull FlutterEngine engine) {
        super.configureFlutterEngine(engine);
        retained = engine;
        channel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), "tomi/mobile");
        events=channel;
        channel.setMethodCallHandler((call, result) -> {
            try {
                String id = call.argument("id");
                switch (call.method) {
                    case "qrCode":
                        result.success(TomiLinks.png(call.argument("url")));break;
                    case "shareQr":
                        TomiLinks.share(this,call.argument("url"));result.success(null);break;
                    case "takeDeepLink":
                        String link=getPreferences(0).getString("pendingLink",null);
                        getPreferences(0).edit().remove("pendingLink").apply();result.success(link);break;
                    case "deviceCheck":
                        result.success(TomiDeviceTools.inspect(this));break;
                    case "screenPrivacy":
                        TomiDeviceTools.privacy(this,Boolean.TRUE.equals(call.argument("enabled")));result.success(null);break;
                    case "prepareVoiceAudio":
                        String voiceStatus=TomiVoiceAudio.prepare(this,Boolean.TRUE.equals(call.argument("recording")));
                        if("busy".equals(voiceStatus)){result.error("AUDIO_BUSY","أنه المكالمة أو غادر الغرفة قبل التسجيل.",null);break;}
                        if("muted".equals(voiceStatus)){result.error("MIC_MUTED","الميكروفون مكتوم من إعدادات الهاتف.",null);break;}
                        if("unavailable".equals(voiceStatus)){result.error("AUDIO_UNAVAILABLE","تعذّر تجهيز صوت الهاتف.",null);break;}
                        result.success("ready".equals(voiceStatus));break;
                    case "shareText":
                        String sharedText=call.argument("text");
                        if(sharedText==null || sharedText.length()>10000){result.error("INVALID_SHARE","تعذّر المشاركة.",null);break;}
                        Intent share=new Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT,sharedText);
                        startActivity(Intent.createChooser(share,"مشاركة عبر"));result.success(null);break;
                    case "presentNotification":
                        Map<String,String> notification=call.argument("data");
                        if(notification!=null)TomiUpdateNotifications.show(this,notification);
                        result.success(null);break;
                    case "notificationSettings":
                        Intent settings=new Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(android.provider.Settings.EXTRA_APP_PACKAGE,getPackageName());
                        startActivity(settings);result.success(null);break;
                    case "takeNotification":
                        String pending=getPreferences(0).getString("pendingNotification",null);
                        if(pending==null){result.success(null);break;}
                        JSONObject pendingJson=new JSONObject(pending);
                        String active=getSharedPreferences("tomi.mobile",0).getString("accountId",null);
                        if(active==null){result.success(null);break;}
                        getPreferences(0).edit().remove("pendingNotification").apply();
                        if(!active.equals(pendingJson.optString("accountId"))){result.success(null);break;}
                        Map<String,Object> openedNotification=new HashMap<>();
                        for(java.util.Iterator<String> keys=pendingJson.keys();keys.hasNext();){String key=keys.next();openedNotification.put(key,pendingJson.get(key));}
                        result.success(openedNotification);break;
                    case "startAudio":
                        if (!TomiCallNotifications.visible || id == null) { result.success(false); break; }
                        Intent service = new Intent(this, TomiAudioService.class)
                            .putExtra("id", id).putExtra("kind", (String) call.argument("kind"))
                            .putExtra("microphone", Boolean.TRUE.equals(call.argument("microphone")));
                        if (pendingAudioResult!=null) { result.success(false);break; }
                        pendingAudio=service;pendingAudioResult=result;
                        android.content.SharedPreferences options=getSharedPreferences("tomi.actions",0);
                        if (android.os.Build.VERSION.SDK_INT>=31 && checkSelfPermission("android.permission.BLUETOOTH_CONNECT")!=android.content.pm.PackageManager.PERMISSION_GRANTED && !options.getBoolean("bluetoothAsked",false)) {
                            options.edit().putBoolean("bluetoothAsked",true).apply();waitingForBluetooth=true;
                            requestPermissions(new String[]{"android.permission.BLUETOOTH_CONNECT"},4711);
                        } else resumeAudioStart();
                        break;
                    case "renewAudio":
                        if (!TomiAudioService.renew(id)) result.error("AUDIO_STOPPED","توقفت خدمة الصوت.",null);
                        else result.success(null);
                        break;
                    case "stopAudio":
                        if (pendingAudio!=null && java.util.Objects.equals(id,pendingAudio.getStringExtra("id"))) cancelAudioStart();
                        TomiAudioService.stop(this, id); result.success(null); break;
                    case "bind":
                        TomiCallNotifications.bind(this, call.argument("accountId"), call.argument("bindingId"), Boolean.TRUE.equals(call.argument("enabled")));
                        result.success(null); break;
                    case "clearCall": TomiCallNotifications.clear(this, id); result.success(null); break;
                    case "takeAction":
                        String raw = getPreferences(0).getString("pendingAction", null);
                        Map<String,Object> data = null;
                        if (raw != null) {
                            data = new HashMap<>(); JSONObject json = new JSONObject(raw);
                            for (java.util.Iterator<String> keys=json.keys();keys.hasNext();) { String k=keys.next();data.put(k,json.get(k)); }
                            String action=(String)data.get("action");
                            // A cold-start answer waits for Dart's successful
                            // device/session registration. Keep the action if
                            // restoration temporarily has no network.
                            if (!"end".equals(action) && !"leave".equals(action) && getSharedPreferences("tomi.mobile",0).getString("bindingId",null)==null) {
                                result.success(null); break;
                            }
                            getPreferences(0).edit().remove("pendingAction").apply();
                        }
                        result.success(data); break;
                    default: result.notImplemented();
                }
            } catch (Exception e) { result.error("MOBILE_UNAVAILABLE", "تعذّر تفعيل خدمة الصوت أو الإشعار.", null); }
        });
    }
    @Override protected void onCreate(Bundle state) { super.onCreate(state); TomiDeviceTools.restore(this); TomiUpdateNotifications.channels(this); capture(getIntent()); }
    @Override protected void onNewIntent(@NonNull Intent intent) { super.onNewIntent(intent); setIntent(intent); capture(intent); }
    @Override protected void onResume() { super.onResume(); TomiCallNotifications.visible=true;resumeAudioStart(); }
    @Override protected void onPause() { TomiCallNotifications.visible=false; super.onPause(); }
    @Override public void onRequestPermissionsResult(int code,@NonNull String[] permissions,@NonNull int[] grants) {
        super.onRequestPermissionsResult(code,permissions,grants);
        if (code==4711) { waitingForBluetooth=false;resumeAudioStart(); }
    }
    private void resumeAudioStart() {
        if (!TomiCallNotifications.visible || waitingForBluetooth || pendingAudioResult==null) return;
        Intent intent=pendingAudio;MethodChannel.Result result=pendingAudioResult;
        pendingAudio=null;pendingAudioResult=null;
        // Bluetooth refusal does not prevent microphone/receiver audio.
        TomiAudioService.start(this,intent,result);
    }
    private void cancelAudioStart() {
        MethodChannel.Result result=pendingAudioResult;pendingAudio=null;pendingAudioResult=null;
        if (result!=null) result.success(false);
    }
    @Override protected void onDestroy() { cancelAudioStart();super.onDestroy(); }
    private void capture(Intent intent) {
        String link=intent.getDataString();
        if(Intent.ACTION_VIEW.equals(intent.getAction()) && TomiLinks.valid(link)){
            getPreferences(0).edit().putString("pendingLink",link).apply();intent.setData(null);
            Map<String,Object> linkEvent=new HashMap<>();linkEvent.put("type","deepLink");dispatch(linkEvent);
        }
        String notification=intent.getStringExtra("tomiNotification");
        if(notification!=null){
            String secret=getSharedPreferences("tomi.actions",0).getString("secret",null);
            if(MobilePolicy.action(intent.getStringExtra("tomiNonce"),secret)){
                getPreferences(0).edit().putString("pendingNotification",notification).apply();
                Map<String,Object> event=new HashMap<>();event.put("type","notification");dispatch(event);
            }
            intent.removeExtra("tomiNotification");
        }
        String action=intent.getStringExtra("tomiAction"), id=intent.getStringExtra("callId"), account=intent.getStringExtra("accountId");
        if (action == null || id == null || account == null) return;
        String nonce=getSharedPreferences("tomi.actions",0).getString("secret",null);
        if (!MobilePolicy.action(intent.getStringExtra("tomiNonce"),nonce)) return;
        if ("answer".equals(action)||"decline".equals(action)) TomiCallNotifications.clear(this,id);
        Map<String,Object> data=new HashMap<>(); data.put("action",action);data.put("callId",id);data.put("accountId",account);
        data.put("bindingId",intent.getStringExtra("bindingId"));data.put("type","call");
        // Persist until Dart has restored and validated the account; do not
        // issue unauthenticated accept/decline requests from a receiver.
        getPreferences(0).edit().putString("pendingAction",new JSONObject(data).toString()).apply();
        intent.removeExtra("tomiAction");
        if (channel != null) channel.invokeMethod("action",data);
    }
}
