import {performance,monitorEventLoopDelay} from 'node:perf_hooks';

const limits=[25,50,100,250,500,1000,5000,Infinity];
export function createOperations(){
  const startedAt=new Date().toISOString(),minutes=new Map(),lag=monitorEventLoopDelay({resolution:20});
  lag.enable();let cache=null,cachedAt=0;
  function track(request,response){
    const start=performance.now(),raw=request.url?.split('?')[0]??'',found=/^\/v1\/(auth|posts|comments|media|chats|chat|calls|rooms|reports|admin|moderation|identity|community|me|users)(?:\/|$)/.exec(raw);
    const group=found?.[1]??(raw==='/health'||raw==='/'?'health':'other');
    response.once('finish',()=>{
      const minute=Math.floor(Date.now()/60000),duration=Math.max(0,performance.now()-start);
      for(const key of minutes.keys())if(key<minute-59)minutes.delete(key);
      const data=minutes.get(minute)??{requests:0,errors:0,clientErrors:0,durationMs:0,histogram:Array(limits.length).fill(0),groups:{},security:{unauthorized:0,forbidden:0,throttled:0,invalid:0}};
      data.security.unauthorized+=Number(response.statusCode===401);data.security.forbidden+=Number(response.statusCode===403);data.security.throttled+=Number(response.statusCode===429);data.security.invalid+=Number([400,413,415].includes(response.statusCode));
      data.requests++;data.errors+=Number(response.statusCode>=500);data.clientErrors+=Number(response.statusCode>=400&&response.statusCode<500);data.durationMs+=duration;
      data.histogram[limits.findIndex(v=>duration<=v)]++;data.groups[group]=(data.groups[group]??0)+1;minutes.set(minute,data);
    });
  }
  async function snapshot(db){
    const total={requests:0,errors:0,clientErrors:0,durationMs:0,histogram:Array(limits.length).fill(0),groups:{},security:{unauthorized:0,forbidden:0,throttled:0,invalid:0}};
    for(const [minute,data] of minutes){if(minute<Math.floor(Date.now()/60000)-59)continue;
      for(const k of Object.keys(total.security))total.security[k]+=data.security[k];
      for(const key of ['requests','errors','clientErrors','durationMs'])total[key]+=data[key];
      for(let i=0;i<limits.length;i++)total.histogram[i]+=data.histogram[i];
      for(const [key,value] of Object.entries(data.groups))total.groups[key]=(total.groups[key]??0)+value;
    }
    let count=0,p95UpperMs=null;
    for(let i=0;i<limits.length;i++){count+=total.histogram[i];if(total.requests&&count>=total.requests*.95){p95UpperMs=Number.isFinite(limits[i])?limits[i]:null;break;}}
    if(!cache||Date.now()-cachedAt>10000){
      const row=(await db.query(`SELECT
        (SELECT COUNT(*) FROM tomi_users u WHERE NOT EXISTS(SELECT 1 FROM tomi_deleted_accounts d WHERE d.user_id=u.id)) users,
        (SELECT COUNT(*) FROM tomi_deleted_accounts) deleted_accounts,
        (SELECT COUNT(*) FROM tomi_erasure_media) pending_erasure_media,
        (SELECT COUNT(*) FROM tomi_account_restrictions a WHERE suspended=1 AND NOT EXISTS(SELECT 1 FROM tomi_deleted_accounts d WHERE d.user_id=a.user_id)) suspended_users,
        (SELECT COUNT(*) FROM tomi_posts) posts,
        (SELECT COUNT(*) FROM tomi_content_moderation x JOIN tomi_posts p ON p.id=x.target_id WHERE x.target_type='post' AND x.hidden=1) hidden_posts,
        (SELECT COUNT(*) FROM tomi_voice_rooms WHERE state='open') open_rooms,
        (SELECT COUNT(*) FROM tomi_voice_members WHERE state='active') room_participants,
        (SELECT COUNT(*) FROM tomi_calls WHERE state<>'ended') active_calls,
        (SELECT COUNT(*) FROM tomi_reports WHERE status IN('open','reviewing')) pending_reports,
        (SELECT COUNT(*) FROM tomi_voice_jobs) pending_voice_jobs,
        (SELECT COALESCE(SUM(byte_length),0) FROM tomi_image_uploads) image_bytes,
        (SELECT COALESCE(SUM(byte_length),0) FROM tomi_audio_uploads) audio_bytes,
        (SELECT COALESCE(SUM(byte_length),0) FROM tomi_video_uploads) video_bytes`)).rows[0];
      cache=Object.fromEntries(Object.entries(row).map(([k,v])=>[k,Number(v)]));cachedAt=Date.now();
    }
    const clientPerformance=(await db.query('SELECT day,kind,area,bucket,build,total FROM tomi_client_metrics WHERE day>=? ORDER BY day DESC,total DESC LIMIT 100',[new Date(Date.now()-7*86400000).toISOString().slice(0,10)])).rows;
    const memory=process.memoryUsage();
    return {security:{...total.security,windowMinutes:60,scope:'this_api_process',warning:total.security.throttled>=20||total.security.forbidden>=50||total.security.unauthorized>=100},clientPerformance,serverTime:new Date().toISOString(),startedAt,windowMinutes:60,scope:'this_api_process',
      requests:{count:total.requests,serverErrors:total.errors,clientErrors:total.clientErrors,averageMs:total.requests?Math.round(total.durationMs/total.requests):0,p95UpperMs,p95OverFiveSeconds:total.requests>0&&p95UpperMs===null,groups:total.groups},
      process:{uptimeSeconds:Math.floor(process.uptime()),rssBytes:memory.rss,heapUsedBytes:memory.heapUsed,eventLoopP95Ms:Number((lag.percentile(95)/1e6).toFixed(2))},
      database:cache,databaseSampleAt:new Date(cachedAt).toISOString(),usageNote:'Recorded media sizes estimate stored objects; these are not provider invoices or participant-minute totals.'};
  }
  return {track,snapshot,close(){lag.disable();}};
}
