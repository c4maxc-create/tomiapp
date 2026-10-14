import {createHmac} from 'node:crypto';

// Credentials cover the two-hour call limit, and are issued only to its claimed sessions.
export const turnLifetime = 7500;
const urls = (raw, pattern) => {
  const list = raw.split(',').map(s => s.trim()).filter(Boolean);
  if (!list.length || list.length > 10 || list.some(s => s.length > 300 || !pattern.test(s))) throw Error('CALL_TURN_CONFIG_INVALID');
  return list;
};
const turnUrl = /^turns?:[a-zA-Z0-9.-]+(?::\d{1,5})?(?:\?transport=(?:udp|tcp))?$/;
const stunUrl = /^stuns?:[a-zA-Z0-9.-]+(?::\d{1,5})?$/;
export function iceFromEnvironment(env=process.env, {fetcher=fetch}={}) {
  const cf = [env.CALL_TURN_KEY_ID, env.CALL_TURN_API_TOKEN];
  const own = [env.CALL_TURN_URLS, env.CALL_TURN_SECRET];
  if (cf.some(Boolean) && !cf.every(Boolean) || own.some(Boolean) && !own.every(Boolean) || cf.some(Boolean) && own.some(Boolean)) throw Error('CALL_TURN_CONFIG_INVALID');
  const policy = env.CALL_FORCE_RELAY === 'true' ? 'relay' : 'all';
  if (cf.every(Boolean)) {
    if (!/^[a-zA-Z0-9_-]{8,128}$/.test(cf[0]) || cf[1].length < 20 || /\s/.test(cf[1])) throw Error('CALL_TURN_CONFIG_INVALID');
    return async () => {
      const r = await fetcher(`https://rtc.live.cloudflare.com/v1/turn/keys/${cf[0]}/credentials/generate-ice-servers`, {
        method:'POST', headers:{authorization:'Bearer '+cf[1], 'content-type':'application/json'},
        body:JSON.stringify({ttl:turnLifetime}), signal:AbortSignal.timeout(10000), redirect:'error',
      });
      if (!r.ok) throw Error('CALL_TURN_UNAVAILABLE');
      const data = await r.json();
      if (!Array.isArray(data.iceServers) || data.iceServers.length > 10) throw Error('CALL_TURN_RESPONSE');
      let relay = false;
      const iceServers = data.iceServers.map(s => {
        const list = Array.isArray(s.urls) ? s.urls : [s.urls];
        if (!list.length || list.length > 10 || list.some(u => typeof u !== 'string' || u.length > 300 || !(turnUrl.test(u) || stunUrl.test(u)))) throw Error('CALL_TURN_RESPONSE');
        if (list.some(u => turnUrl.test(u))) {
          if (typeof s.username !== 'string' || typeof s.credential !== 'string' || !s.username || !s.credential || s.username.length > 1024 || s.credential.length > 1024) throw Error('CALL_TURN_RESPONSE');
          relay = true;
          return {urls:list,username:s.username,credential:s.credential};
        }
        return {urls:list};
      });
      if (!relay) throw Error('CALL_TURN_RESPONSE');
      return {iceServers,iceTransportPolicy:policy};
    };
  }
  if (own.every(Boolean)) {
    if (own[1].length < 32 || own[1].length > 512) throw Error('CALL_TURN_CONFIG_INVALID');
    const turn = urls(own[0],turnUrl), stun = env.CALL_STUN_URLS ? urls(env.CALL_STUN_URLS,stunUrl) : [];
    return async ({userId,callId}) => {
      const username = `${Math.floor(Date.now()/1000)+turnLifetime}:${userId}:${callId}`;
      return {iceServers:[...(stun.length?[{urls:stun}]:[]),{urls:turn,username,credential:createHmac('sha1',own[1]).update(username).digest('base64')}],iceTransportPolicy:policy};
    };
  }
  return null;
}
