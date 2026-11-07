import {timingSafeEqual,createHash} from 'node:crypto';
import {isIP} from 'node:net';
import {ApiError} from './security.mjs';
export function clientIp(request,trustProxy=false,edgeSecret=null){
 const peer=request.socket.remoteAddress||'unknown';
 if(edgeSecret&&request.headers['x-tomi-edge']){verifyEdge(request,edgeSecret);const forwarded=request.headers['x-tomi-client-ip'];return typeof forwarded==='string'&&isIP(forwarded)?forwarded:peer;}
 if(!trustProxy)return peer;
 const raw=request.headers['x-forwarded-for'];
 if(typeof raw!=='string'||raw.length>2048)return peer;
 const closest=raw.split(',').at(-1).trim();return isIP(closest)?closest:peer;
}
export function validateJsonShape(value){
 const stack=[[value,0]];
 while(stack.length){const [node,depth]=stack.pop();if(node===null||typeof node!=='object')continue;
  if(depth>32)throw new ApiError(400,'BAD_JSON','بنية الطلب أعمق من المسموح.');
  for(const key of Object.keys(node)){
   if(['__proto__','prototype','constructor'].includes(key))throw new ApiError(400,'BAD_JSON','حقول الطلب غير مسموحة.');
   if(node[key]!==null&&typeof node[key]==='object')stack.push([node[key],depth+1]);
  }
 }
 return value;
}

export function verifyEdge(request,secret){
 if(!secret)return;
 const value=request.headers['x-tomi-edge'];
 const hash=v=>createHash('sha256').update(v).digest();
 if(typeof value!=='string'||value.length>256||!timingSafeEqual(hash(value),hash(secret)))throw new ApiError(403,'ORIGIN_DENIED','الطلب غير مسموح.');
}
export function edgeKey(value){if(!value)return null;if(!/^[A-Za-z0-9_-]{43}$/.test(value))throw Error('TOMI_EDGE_SECRET must be a random 32-byte base64url value');return value;}
