import {isIP} from 'node:net';
import {ApiError} from './security.mjs';
export function clientIp(request,trustProxy=false){
 const peer=request.socket.remoteAddress||'unknown';
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
