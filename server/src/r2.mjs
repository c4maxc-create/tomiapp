import { createHash,createHmac } from 'node:crypto';
import { ApiError } from './security.mjs';
import { imageDimensions,maxImageBytes } from './images.mjs';
const encode=v=>encodeURIComponent(v).replace(/[!'()*]/g,c=>'%'+c.charCodeAt(0).toString(16).toUpperCase());
const hmac=(key,value)=>createHmac('sha256',key).update(value).digest();
const hash=value=>createHash('sha256').update(value).digest('hex');
// Native S3 SigV4. PUT signs type, checksum and the create-only precondition.
export function signS3Url({endpoint,bucket,key,accessKeyId,secretAccessKey,method='GET',headers={},expires=900,now=new Date(),region='auto'}) {
 const url=new URL(endpoint);url.pathname='/'+[...(bucket?[bucket]:[]),...key.split('/')].map(encode).join('/');
 const date=now.toISOString().replace(/[:-]|\.\d{3}/g,'');const day=date.slice(0,8),scope=day+'/'+region+'/s3/aws4_request';
 const normalized={host:url.host};
 for(const [k,v] of Object.entries(headers))normalized[k.toLowerCase()]=String(v).trim().replace(/\s+/g,' ');
 const names=Object.keys(normalized).sort(),signedHeaders=names.join(';');
 const query=[['X-Amz-Algorithm','AWS4-HMAC-SHA256'],['X-Amz-Credential',accessKeyId+'/'+scope],['X-Amz-Date',date],['X-Amz-Expires',String(expires)],['X-Amz-SignedHeaders',signedHeaders]]
  .map(([k,v])=>[encode(k),encode(v)]).sort((a,b)=>a[0]<b[0]?-1:1).map(([k,v])=>k+'='+v).join('&');
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
 return new R2Images({endpoint:'https://'+env.R2_ACCOUNT_ID+'.r2.cloudflarestorage.com',bucket:env.R2_BUCKET_NAME,accessKeyId:env.R2_ACCESS_KEY_ID,secretAccessKey:env.R2_SECRET_ACCESS_KEY,publicBaseUrl});
}
export class R2Images {
 constructor(config,{fetcher=fetch}={}){this.config=config;this.fetcher=fetcher;this.active=0;}
 url(method,key,headers={},expires=900){return signS3Url({...this.config,method,key,headers,expires});}
 prepare(u){const headers={'content-type':u.content_type,'content-md5':u.content_md5,'if-none-match':'*'};return{uploadUrl:this.url('PUT',u.object_key,headers),headers,expiresIn:900};}
 readUrl(key){return this.config.publicBaseUrl?this.config.publicBaseUrl+'/'+key.split('/').map(encode).join('/'):this.url('GET',key,{},86400);}
 async verify(u){
  if(this.active>=2)throw new ApiError(503,'MEDIA_BUSY','الصور قيد المعالجة؛ جرّب النشر بعد قليل.');
  this.active++;const abort=new AbortController(),deadline=setTimeout(()=>abort.abort(),30000);
  try{
   const response=await this.fetcher(this.url('GET',u.object_key),{signal:abort.signal,redirect:'error'});
   if(!response.ok){await response.body?.cancel();throw new ApiError(response.status===404?409:503,response.status===404?'UPLOAD_INCOMPLETE':'MEDIA_UNAVAILABLE','تعذّر التحقق من الصورة؛ جرّب النشر مرة ثانية.');}
   const type=(response.headers.get('content-type')||'').split(';')[0].trim().toLowerCase(),length=Number(response.headers.get('content-length'));
   if(type!==u.content_type||length!==Number(u.byte_length)||length>maxImageBytes){await response.body?.cancel();throw new ApiError(400,'INVALID_IMAGE','حجم الصورة أو نوعها تغيّر؛ اختَرها مرة ثانية.');}
   const checksum=createHash('md5'),prefix=[];let size=0,prefixSize=0;
   for await(const chunk of response.body){
    size+=chunk.length;if(size>length||size>maxImageBytes){abort.abort();throw new ApiError(400,'INVALID_IMAGE','الصورة أكبر من المسموح.');}
    checksum.update(chunk);
    if(prefixSize<262144){const part=Buffer.from(chunk.subarray(0,262144-prefixSize));prefix.push(part);prefixSize+=part.length;}
   }
   if(size!==length||checksum.digest('base64')!==u.content_md5)throw new ApiError(400,'INVALID_IMAGE','الصورة غير مكتملة؛ اختَرها مرة ثانية.');
   return imageDimensions(Buffer.concat(prefix),type);
  }catch(e){if(e instanceof ApiError)throw e;throw new ApiError(503,'MEDIA_UNAVAILABLE','تعذّر التحقق من الصورة؛ جرّب النشر مرة ثانية.');}
  finally{clearTimeout(deadline);this.active--;}
 }
 async delete(key){const r=await this.fetcher(this.url('DELETE',key),{method:'DELETE',signal:AbortSignal.timeout(10000),redirect:'error'});await r.body?.cancel();if(!r.ok&&r.status!==404)throw new Error('R2_DELETE_FAILED');}
}
