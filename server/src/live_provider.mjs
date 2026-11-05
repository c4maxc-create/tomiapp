import {AccessToken,RoomServiceClient,TrackSource} from 'livekit-server-sdk';
export function liveProviderFromEnvironment(env=process.env,{client}={}){
 const names=['ROOM_LIVEKIT_URL','ROOM_LIVEKIT_API_KEY','ROOM_LIVEKIT_API_SECRET'].some(k=>env[k]?.trim())?['ROOM_LIVEKIT_URL','ROOM_LIVEKIT_API_KEY','ROOM_LIVEKIT_API_SECRET']:['LIVEKIT_URL','LIVEKIT_API_KEY','LIVEKIT_API_SECRET'];
 const [raw,key,secret]=names.map(k=>env[k]?.trim());if(!raw&&!key&&!secret)return null;
 const url=new URL(raw);if(url.protocol!=='wss:'||!/^[a-z0-9-]+\.livekit\.cloud$/.test(url.hostname)||url.port||url.username||url.password||url.search||url.hash||!['','/'].includes(url.pathname)||!key||!secret)throw Error('LIVE_CONFIG_INVALID');
 const service=client??new RoomServiceClient('https://'+url.hostname,key,secret,{requestTimeout:5,failover:false});
 return {async grant(room,identity,publish){const t=new AccessToken(key,secret,{identity,ttl:60});t.addGrant({room,roomJoin:true,canSubscribe:true,canPublish:publish,canPublishData:false,canPublishSources:[TrackSource.CAMERA,TrackSource.MICROPHONE]});return {url:raw,token:await t.toJwt(),room,identity,publish};},async remove(room,identity){try{await service.removeParticipant(room,identity);}catch(e){if(e.code!=='not_found')throw e;}},async close(room){try{await service.deleteRoom(room);}catch(e){if(e.code!=='not_found')throw e;}}};
}
