import {mediaScanner} from './media_scanner.mjs';
import { createHash,createHmac } from 'node:crypto';
import { ApiError } from './security.mjs';
import { imageDimensions,maxImageBytes } from './images.mjs';
import {audioMetadata,maxAudioBytes} from './audio.mjs';
import {VideoInspector,maxVideoBytes} from './video.mjs';
const encode=v=>encodeURIComponent(v).replace(/[!'()*]/g,c=>'%'+c.charCodeAt(0).toString(16).toUpperCase());
const hmac=(key,value)=>createHmac('sha256',key).update(value).digest();
const hash=value=>createHash('sha256').update(value).digest('hex');
// Native S3 SigV4. PUT signs type, checksum and the create-only precondition.
export function signS3Url({endpoint,bucket,key,accessKeyId,secretAccessKey,method='GET',headers={},expires=900,now=new Date(),region='auto',parameters={}}) {
 const url=new URL(endpoint);url.pathname='/'+[...(bucket?[bucket]:[]),...key.split('/')].map(encode).join('/');
 const date=now.toISOString().replace(/[:-]|\.\d{3}/g,'');const day=date.slice(0,8),scope=day+'/'+region+'/s3/aws4_request';
 const normalized={host:url.host};
 for(const [k,v] of Object.entries(headers))normalized[k.toLowerCase()]=String(v).trim().replace(/\s+/g,' ');
 const names=Object.keys(normalized).sort(),signedHeaders=names.join(';');
 const query=[...Object.entries(parameters),['X-Amz-Algorithm','AWS4-HMAC-SHA256'],['X-Amz-Credential',accessKeyId+'/'+scope],['X-Amz-Date',date],['X-Amz-Expires',String(expires)],['X-Amz-SignedHeaders',signedHeaders]]
  .map(([k,v])=>[encode(k),encode(v)]).sort((a,b)=>a[0]===b[0]?(a[1]<b[1]?-1:1):(a[0]<b[0]?-1:1)).map(([k,v])=>k+'='+v).join('&');
 const canonical=[method,url.pathname,query,names.map(k=>k+':'+normalized[k]+'\n').join(''),signedHeaders,'UNSIGNED-PAYLOAD'].join('\n');
 const signing=hmac(hmac(hmac(hmac('AWS4'+secretAccessKey,day),region),'s3'),'aws4_request');
 const signature=createHmac('sha256',signing).update(['AWS4-HMAC-SHA256',date,scope,hash(canonical)].join('\n')).digest('hex');
 url.search=query+'&X-Amz-Signature='+signature;return url.toString();
}
export function r2FromEnvironment(env=process.env){
 const fields=['R2_ACCOUNT_ID','R2_BUCKET_NAME','R2_ACCESS_KEY_ID','R2_SECRET_ACCESS_KEY'];
 if(fields.every(k=>!env[k]))return null;
 if(fields.some(k=>!env[k]))throw new Error('Complete all four R2 environment variables or leave them all unset.');
 if(!/^[a-f0-9]{32}$/i.test(env.R2_ACCOUNT_ID)||!/^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$/.test(env.R2_BUCKET_NAME))throw new Error('Invalid R2 account ID or bucket.');
 let publicBaseUrl;
 if(env.R2_PUBLIC_BASE_URL){const u=new URL(env.R2_PUBLIC_BASE_URL);if(u.protocol!=='https:'||u.username||u.password||u.search||u.hash)throw new Error('Invalid public R2 HTTPS URL.');publicBaseUrl=u.toString().replace(/\/+$/,'');}
 return new R2Images({endpoint:'https://'+env.R2_ACCOUNT_ID+'.r2.cloudflarestorage.com',bucket:env.R2_BUCKET_NAME,accessKeyId:env.R2_ACCESS_KEY_ID,secretAccessKey:env.R2_SECRET_ACCESS_KEY,publicBaseUrl},{scanner:mediaScanner(env.TOMI_CLAMSCAN_BINARY)});
}
export function chatR2FromEnvironment(env=process.env,fallback=null){
 const configured=r2FromEnvironment({TOMI_CLAMSCAN_BINARY:env.TOMI_CLAMSCAN_BINARY,R2_ACCOUNT_ID:env.R2_CHAT_ACCOUNT_ID,R2_BUCKET_NAME:env.R2_CHAT_BUCKET_NAME,R2_ACCESS_KEY_ID:env.R2_CHAT_ACCESS_KEY_ID,R2_SECRET_ACCESS_KEY:env.R2_CHAT_SECRET_ACCESS_KEY});
 if(fallback?.config?.publicBaseUrl){if(!configured)return null;if(configured.config.endpoint===fallback.config.endpoint&&configured.config.bucket===fallback.config.bucket)throw new Error('Chat images need a separate private bucket.');}
 return configured||fallback;
}
export class R2Images {
 supportsMultipart=true;
 constructor(config,{fetcher=fetch,scanner=null}={}){this.config=config;this.fetcher=fetcher;this.active=0;this.scanner=scanner;}
 url(method,key,headers={},expires=900){return signS3Url({...this.config,method,key,headers,expires});}
 prepare(u){const headers={'content-type':u.content_type,'content-md5':u.content_md5,'if-none-match':'*'};return{uploadUrl:this.url('PUT',u.object_key,headers),headers,expiresIn:900};}
 readUrl(key){return this.config.publicBaseUrl?this.config.publicBaseUrl+'/'+key.split('/').map(encode).join('/'):this.url('GET',key,{},86400);}
 privateReadUrl(key){return this.url('GET',key,{},300);}
 avatarUrl(key){return this.config.publicBaseUrl?this.readUrl(key):signS3Url({...this.config,method:'GET',key,expires:86400,now:new Date(Math.floor(Date.now()/600000)*600000)});}
 multipartUrl(method,key,parameters,headers={}){return signS3Url({...this.config,method,key,parameters,headers,expires:900});}
 async multipartRequest(method,key,parameters,headers={},body){const r=await this.fetcher(this.multipartUrl(method,key,parameters,headers),{method,headers,body,signal:AbortSignal.timeout(30000),redirect:'error'});if(!r.ok){await r.body?.cancel();throw new ApiError(r.status===404?409:503,r.status===404?'MULTIPART_MISSING':'MEDIA_UNAVAILABLE','تعذّر استكمال الرفع؛ أعد المحاولة.');}const text=await r.text();if(text.length>65536||/<Error(?:\s|>)/.test(text))throw new ApiError(503,'MEDIA_UNAVAILABLE','تعذّر تأكيد رفع الملف.');return text;}
 async startMultipart(u){const xml=await this.multipartRequest('POST',u.object_key,{uploads:''},{'content-type':u.content_type});const raw=/<UploadId>([^<]{1,8192})<\/UploadId>/.exec(xml)?.[1],id=raw?.replace(/&quot;/g,'\"').replace(/&apos;/g,"'").replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&amp;/g,'&');if(!id||!/^[\x21-\x7e]{1,2048}$/.test(id))throw new ApiError(503,'MEDIA_UNAVAILABLE','استجابة رفع غير صحيحة.');return id;}
 async listMultipart(key,uploadId){const xml=await this.multipartRequest('GET',key,{uploadId});const result=[];for(const match of xml.matchAll(/<Part>([\s\S]*?)<\/Part>/g)){const p=match[1],number=Number(/<PartNumber>(\d+)<\/PartNumber>/.exec(p)?.[1]),size=Number(/<Size>(\d+)<\/Size>/.exec(p)?.[1]),etag=/<ETag>([^<]+)<\/ETag>/.exec(p)?.[1]?.replace(/&quot;/g,'"');if(!Number.isSafeInteger(number)||number<1||number>100||!Number.isSafeInteger(size)||!/^"?[a-fA-F0-9]{32}"?$/.test(etag??''))throw new ApiError(503,'MEDIA_UNAVAILABLE','أجزاء رفع غير صحيحة.');result.push({number,size,etag});}return result;}
 partMultipart(key,uploadId,number){return this.multipartUrl('PUT',key,{uploadId,partNumber:String(number)});}
 async finishMultipart(key,uploadId,parts){const body='<CompleteMultipartUpload>'+parts.map(p=>'<Part><PartNumber>'+p.number+'</PartNumber><ETag>'+p.etag.replaceAll('"','&quot;')+'</ETag></Part>').join('')+'</CompleteMultipartUpload>';await this.multipartRequest('POST',key,{uploadId},{'content-type':'application/xml','if-none-match':'*'},body);}
 async hasMultipartObject(u){const r=await this.fetcher(this.url('HEAD',u.object_key),{method:'HEAD',signal:AbortSignal.timeout(10000),redirect:'error'});await r.body?.cancel();if(r.status===404)return false;if(!r.ok)throw new ApiError(503,'MEDIA_UNAVAILABLE','تعذّر التحقق من الملف.');if(Number(r.headers.get('content-length'))!==Number(u.byte_length)||(r.headers.get('content-type')??'').split(';')[0]!==u.content_type)throw new ApiError(400,'INVALID_FILE','حجم الملف أو نوعه تغير.');return true;}
 async abortMultipart(key,uploadId){try{await this.multipartRequest('DELETE',key,{uploadId});}catch(e){if(e.code!=='MULTIPART_MISSING')throw e;}}
 async verifyAudio(u){
  let scan;
  if(this.active>=2)throw new ApiError(503,'MEDIA_BUSY','الصوت قيد المعالجة؛ جرّب بعد قليل.');this.active++;const abort=new AbortController(),timer=setTimeout(()=>abort.abort(),30000);
  try{scan=await this.scanner?.begin();const r=await this.fetcher(this.url('GET',u.object_key),{signal:abort.signal,redirect:'error'});if(!r.ok){await r.body?.cancel();throw new ApiError(r.status===404?409:503,r.status===404?'UPLOAD_INCOMPLETE':'MEDIA_UNAVAILABLE','تعذّر التحقق من التسجيل.');}const length=Number(r.headers.get('content-length')),type=(r.headers.get('content-type')||'').split(';')[0].trim().toLowerCase();if(length!==Number(u.byte_length)||length>maxAudioBytes||type!=='audio/mp4'){await r.body?.cancel();throw new ApiError(400,'INVALID_AUDIO','حجم التسجيل أو نوعه تغيّر.');}let size=0;const pieces=[],md5=createHash('md5'),sha=createHash('sha256');for await(const piece of r.body){await scan?.write(piece);size+=piece.length;if(size>length||size>maxAudioBytes){abort.abort();throw new ApiError(400,'INVALID_AUDIO','التسجيل أكبر من المسموح.');}md5.update(piece);sha.update(piece);pieces.push(Buffer.from(piece));}if(size!==length||md5.digest('base64')!==u.content_md5||u.content_sha256&&sha.digest('hex')!==u.content_sha256)throw new ApiError(400,'INVALID_AUDIO','التسجيل غير مكتمل.');const metadata=audioMetadata(Buffer.concat(pieces));await scan?.finish();return metadata;}catch(e){if(e instanceof ApiError)throw e;throw new ApiError(503,'MEDIA_UNAVAILABLE','تعذّر التحقق من التسجيل؛ جرّب مرة ثانية.');}finally{await scan?.abort();clearTimeout(timer);this.active--;}
 }
 async verifyVideo(u){
  let scan;
  if(this.active>=2)throw new ApiError(503,'MEDIA_BUSY','الفيديو قيد المعالجة؛ جرّب بعد قليل.');this.active++;const abort=new AbortController(),timer=setTimeout(()=>abort.abort(),60000);
  try{
   scan=await this.scanner?.begin();
   const r=await this.fetcher(this.url('GET',u.object_key),{signal:abort.signal,redirect:'error'});if(!r.ok){await r.body?.cancel();throw new ApiError(r.status===404?409:503,r.status===404?'UPLOAD_INCOMPLETE':'MEDIA_UNAVAILABLE','تعذّر التحقق من الفيديو.');}
   const length=Number(r.headers.get('content-length')),type=(r.headers.get('content-type')||'').split(';')[0].trim().toLowerCase();
   if(length!==Number(u.byte_length)||length>maxVideoBytes||type!=='video/mp4'){await r.body?.cancel();throw new ApiError(400,'INVALID_VIDEO','حجم الفيديو أو نوعه تغيّر.');}
   const inspector=new VideoInspector(length),md5=createHash('md5'),sha=createHash('sha256');
   for await(const piece of r.body){await scan?.write(piece);md5.update(piece);sha.update(piece);inspector.push(piece);}
   if(md5.digest('base64')!==u.content_md5||u.content_sha256&&sha.digest('hex')!==u.content_sha256)throw new ApiError(400,'INVALID_VIDEO','الفيديو غير مكتمل أو تغيّر.');
   const metadata=inspector.finish();await scan?.finish();return metadata;
  }catch(e){if(e instanceof ApiError)throw e;throw new ApiError(503,'MEDIA_UNAVAILABLE','تعذّر التحقق من الفيديو؛ جرّب مرة ثانية.');}finally{await scan?.abort();clearTimeout(timer);this.active--;}
 }
 async verify(u){
  let scan;
  if(this.active>=2)throw new ApiError(503,'MEDIA_BUSY','الصور قيد المعالجة؛ جرّب النشر بعد قليل.');
  this.active++;const abort=new AbortController(),deadline=setTimeout(()=>abort.abort(),30000);
  try{
   scan=await this.scanner?.begin();
   const response=await this.fetcher(this.url('GET',u.object_key),{signal:abort.signal,redirect:'error'});
   if(!response.ok){await response.body?.cancel();throw new ApiError(response.status===404?409:503,response.status===404?'UPLOAD_INCOMPLETE':'MEDIA_UNAVAILABLE','تعذّر التحقق من الصورة؛ جرّب النشر مرة ثانية.');}
   const type=(response.headers.get('content-type')||'').split(';')[0].trim().toLowerCase(),length=Number(response.headers.get('content-length'));
   if(type!==u.content_type||length!==Number(u.byte_length)||length>maxImageBytes){await response.body?.cancel();throw new ApiError(400,'INVALID_IMAGE','حجم الصورة أو نوعها تغيّر؛ اختَرها مرة ثانية.');}
   const checksum=createHash('md5'),sha=createHash('sha256'),prefix=[];let size=0,prefixSize=0;
   for await(const chunk of response.body){
    await scan?.write(chunk);
    size+=chunk.length;if(size>length||size>maxImageBytes){abort.abort();throw new ApiError(400,'INVALID_IMAGE','الصورة أكبر من المسموح.');}
    checksum.update(chunk);sha.update(chunk);
    if(prefixSize<262144){const part=Buffer.from(chunk.subarray(0,262144-prefixSize));prefix.push(part);prefixSize+=part.length;}
   }
   if(size!==length||checksum.digest('base64')!==u.content_md5||u.content_sha256&&sha.digest('hex')!==u.content_sha256)throw new ApiError(400,'INVALID_IMAGE','الصورة غير مكتملة؛ اختَرها مرة ثانية.');
   const metadata=imageDimensions(Buffer.concat(prefix),type);await scan?.finish();return metadata;
  }catch(e){if(e instanceof ApiError)throw e;throw new ApiError(503,'MEDIA_UNAVAILABLE','تعذّر التحقق من الصورة؛ جرّب النشر مرة ثانية.');}
  finally{await scan?.abort();clearTimeout(deadline);this.active--;}
 }
 async putDerived(key,bytes){const headers={'content-type':'video/mp4','content-md5':createHash('md5').update(bytes).digest('base64'),'if-none-match':'*'};const r=await this.fetcher(this.url('PUT',key,headers),{method:'PUT',headers,body:bytes,signal:AbortSignal.timeout(30000),redirect:'error'});await r.body?.cancel();if(r.status===412){const head=await this.fetcher(this.url('HEAD',key),{method:'HEAD',signal:AbortSignal.timeout(10000),redirect:'error'});await head.body?.cancel();if(!head.ok||Number(head.headers.get('content-length'))!==bytes.length||(head.headers.get('etag')??'').replaceAll('\"','')!==createHash('md5').update(bytes).digest('hex'))throw Error('VIDEO_DERIVED_CONFLICT');}else if(!r.ok)throw Error('VIDEO_DERIVED_UPLOAD');}
 async delete(key){const r=await this.fetcher(this.url('DELETE',key),{method:'DELETE',signal:AbortSignal.timeout(10000),redirect:'error'});await r.body?.cancel();if(!r.ok&&r.status!==404)throw new Error('R2_DELETE_FAILED');}
}
