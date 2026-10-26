import {AccessToken, RoomServiceClient, TrackSource} from 'livekit-server-sdk';

// Cloud token revocation is required for immediate moderator enforcement. A
// self-hosted server cannot revoke old join tokens and is deliberately refused.
export function roomProviderFromEnvironment(env=process.env,{client}={}) {
  const roomNames=['ROOM_LIVEKIT_URL','ROOM_LIVEKIT_API_KEY','ROOM_LIVEKIT_API_SECRET'];
  const names=roomNames.some(k=>env[k]?.trim())?roomNames:['LIVEKIT_URL','LIVEKIT_API_KEY','LIVEKIT_API_SECRET'];
  const values=names.map(k=>env[k]?.trim());
  if(values.every(v=>!v))return null;
  const [url,key,secret]=values;
  let endpoint;try{endpoint=new URL(url);}catch{}
  if(!endpoint||endpoint.protocol!=='wss:'||!endpoint.hostname.endsWith('.livekit.cloud')||
    !/^[a-z0-9-]+\.livekit\.cloud$/.test(endpoint.hostname)||endpoint.port||endpoint.username||endpoint.password||
    endpoint.search||endpoint.hash||!['','/'].includes(endpoint.pathname)||!key||!secret||secret.length<32)
    throw new Error('Configure all three ROOM_LIVEKIT_* settings (or all three LIVEKIT_* aliases) from the same LiveKit Cloud project.');
  const service=client??new RoomServiceClient('https://'+endpoint.hostname,key,secret,{requestTimeout:5,failover:false});
  const roomName=id=>'tomi-'+id;
  const permission=publish=>({canSubscribe:true,canPublish:publish,canPublishData:false,
    canPublishSources:[TrackSource.MICROPHONE],canUpdateMetadata:false,hidden:false,recorder:false});
  const ignoreMissing=async work=>{try{return await work();}catch(e){if(e.code!=='not_found')throw e;}};
  return {
    async ensure(room){await service.createRoom({name:roomName(room.id),maxParticipants:Number(room.capacity),emptyTimeout:600,departureTimeout:600});},
    async grant(room,member){
      const token=new AccessToken(key,secret,{identity:member.identity,ttl:60});
      token.addGrant({room:roomName(room.id),roomJoin:true,canSubscribe:true,
        canPublish:member.seat!==null&&Number(member.mic_allowed)===1,
        canPublishSources:[TrackSource.MICROPHONE],canPublishData:false,canUpdateOwnMetadata:false});
      return {url:'wss://'+endpoint.hostname,token:await token.toJwt(),identity:member.identity,expiresInSeconds:60};
    },
    async permissions(room,identity,publish){await service.updateParticipant(roomName(room.id),identity,{permission:permission(publish)});},
    async remove(room,identity){await ignoreMissing(()=>service.removeParticipant(roomName(room.id),identity));},
    async close(room){await ignoreMissing(()=>service.deleteRoom(roomName(room.id)));},
  };
}
