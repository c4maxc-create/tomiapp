import {verifyEdge} from './request_security.mjs';
import {WebSocketServer,WebSocket} from 'ws';
export function createRealtime({server,origins,authenticate,validSessions,typing,limit,edgeSecret=null,clientIp=request=>request.socket.remoteAddress}){
 const hub=new WebSocketServer({noServer:true,maxPayload:4096,perMessageDeflate:false});
 const sockets=new Set();
 const attempts=new Map();
 function handshake(ip){
  const now=Date.now();for(const [key,value] of attempts)if(now-value.started>=60000)attempts.delete(key);
  const current=attempts.get(ip);
  if(current){if(++current.hits>60)return false;}
  else {if(attempts.size>=2000)return false;attempts.set(ip,{started:now,hits:1});}
  return [...sockets].filter(ws=>!ws.userId&&ws.clientIp===ip).length<8;
 }
 const emit=(ids,event)=>{const payload=JSON.stringify(event);for(const ws of sockets)if(ids.includes(ws.userId)&&ws.readyState===WebSocket.OPEN){if(ws.bufferedAmount>262144)ws.terminate();else ws.send(payload);}};
 const invalidateSession=hash=>{for(const ws of sockets)if(ws.tokenHash===hash)ws.close(4401,'Session expired');};
 const invalidateUser=id=>{for(const ws of sockets)if(ws.userId===id)ws.close(4401,'Session expired');};
 server.on('upgrade',(request,socket,head)=>{
  try{verifyEdge(request,edgeSecret);}catch{socket.end('HTTP/1.1 403 Forbidden\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');return;}
  let url;try{url=new URL(request.url,'http://tomi.internal');}catch{socket.destroy();return;}
  if(url.pathname!=='/v1/chat/socket'||url.search||(request.headers.origin&&!origins.includes(request.headers.origin))||sockets.size>=500){socket.destroy();return;}
  const ip=clientIp(request);if(!handshake(ip)){socket.end('HTTP/1.1 429 Too Many Requests\r\nConnection: close\r\nRetry-After: 60\r\nContent-Length: 0\r\n\r\n');return;}
  hub.handleUpgrade(request,socket,head,ws=>{ws.clientIp=ip;hub.emit('connection',ws,request);});
 });
 hub.on('connection',(ws,request)=>{
  sockets.add(ws);ws.alive=true;let processing=false,queued=0;
  const timeout=setTimeout(()=>ws.close(4401,'Authenticate first'),5000);timeout.unref();
  ws.on('pong',()=>{ws.alive=true;});
  ws.on('error',()=>{});ws.on('close',()=>{clearTimeout(timeout);sockets.delete(ws);});
  let tail=Promise.resolve();
  ws.on('message',(raw,binary)=>{
   if(binary||++queued>8){ws.close(4400,'Invalid frame');return;}
   tail=tail.then(async()=>{
    if(ws.readyState!==WebSocket.OPEN)return;
    const data=JSON.parse(raw.toString());
    if(!data||Array.isArray(data)||typeof data!=='object')throw Error('frame');
    if(!ws.userId){
     if(processing||data.type!=='authenticate'||typeof data.token!=='string')throw Error('auth');
     processing=true;await limit('ws-ip:'+ws.clientIp,60);
     const current=await authenticate(data.token);
     if([...sockets].filter(other=>other.userId===current.id).length>=4){ws.close(4429,'Connection limit');return;}
     if(ws.readyState!==WebSocket.OPEN)return;
     ws.userId=current.id;ws.tokenHash=current.tokenHash;clearTimeout(timeout);ws.send(JSON.stringify({type:'chat.ready'}));
    }else{
     if(data.type!=='typing'||typeof data.active!=='boolean'||typeof data.conversationId!=='string')throw Error('frame');
     await limit('ws-typing:'+ws.userId,90);
     if(!(await validSessions([ws.tokenHash])).has(ws.tokenHash)){ws.close(4401,'Session expired');return;}
     const activity=data.activity??'typing';if(!['typing','recording','video','image','audio','file'].includes(activity))throw Error('frame');
     await typing(ws.userId,data.conversationId,data.active,activity);
    }
   }).catch(error=>{
    if(!ws.userId)ws.close(4401,'Authentication failed');
    else if(error.code)ws.send(JSON.stringify({type:'chat.error',code:error.code}));
    else ws.close(4400,'Invalid frame');
   }).finally(()=>queued--);
  });
 });
 let checking=false;
 const interval=setInterval(async()=>{
  if(checking)return;checking=true;
  try{
   const hashes=[...new Set([...sockets].map(ws=>ws.tokenHash).filter(Boolean))];
   const valid=hashes.length?await validSessions(hashes):new Set();
   for(const ws of sockets){if(ws.tokenHash&&!valid.has(ws.tokenHash)){ws.close(4401,'Session expired');continue;}
    if(!ws.alive){ws.terminate();continue;}ws.alive=false;ws.ping();}
  }catch{for(const ws of sockets)ws.terminate();}finally{checking=false;}
 },20000);interval.unref();
 const close=()=>{clearInterval(interval);for(const ws of sockets)ws.terminate();hub.close();};
 const original=server.close.bind(server);server.close=(...args)=>{close();return original(...args);};
 return{emit,invalidateSession,invalidateUser,close};
}
