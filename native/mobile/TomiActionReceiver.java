package com.tomi.tomi_app;

import android.content.*;
import java.util.HashMap;
import java.util.Map;

/** Private, immutable notification controls; never starts capture or an engine. */
public class TomiActionReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context,Intent intent) {
        String secret=context.getSharedPreferences("tomi.actions",0).getString("secret",null);
        if (!MobilePolicy.action(intent.getStringExtra("tomiNonce"),secret)) return;
        String action=intent.getStringExtra("tomiAction"),id=intent.getStringExtra("callId");
        if (id==null || !("end".equals(action)||"leave".equals(action))) return;
        Map<String,Object> data=new HashMap<>();data.put("type","control");data.put("action",action);
        data.put("callId",id);data.put("accountId",intent.getStringExtra("accountId"));
        MainActivity.dispatch(data);
        TomiAudioService.stop(context,id);
    }
}
