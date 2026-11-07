// Deploy on the assigned workers.dev hostname or an owned proxied hostname. Keep TOMI_EDGE_SECRET in Worker Secrets.
export async function forward(request,env,fetcher=fetch){
 let origin;try{origin=new URL(env.TOMI_ORIGIN);}catch{return new Response('Unavailable',{status:503});}
 if(origin.protocol!=='https:'||origin.username||origin.password||origin.pathname!=='/'||origin.search||origin.hash||!env.TOMI_EDGE_SECRET)return new Response('Unavailable',{status:503});
 const incoming=new URL(request.url);
 if(incoming.protocol!=='https:'||(env.TOMI_PUBLIC_HOST?incoming.hostname!==env.TOMI_PUBLIC_HOST:!incoming.hostname.endsWith('.workers.dev'))||incoming.hostname===origin.hostname)return new Response('Forbidden',{status:403});
 if(!['GET','HEAD','POST','PUT','PATCH','DELETE','OPTIONS'].includes(request.method))return new Response('Method not allowed',{status:405,headers:{'cache-control':'no-store'}});
 const declared=request.headers.get('content-length');if(declared&&(!/^\d+$/.test(declared)||Number(declared)>1048576))return new Response('Request too large',{status:413,headers:{'cache-control':'no-store'}});
 const upgrade=request.headers.get('upgrade');if(upgrade&&(upgrade.toLowerCase()!=='websocket'||incoming.pathname!=='/v1/chat/socket'))return new Response('Forbidden',{status:403});
 if(env.API_RATE||env.AUTH_RATE){const bytes=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(env.TOMI_EDGE_SECRET+'|'+(request.headers.get('cf-connecting-ip')??'unknown')));const key=Array.from(new Uint8Array(bytes),b=>b.toString(16).padStart(2,'0')).join('');
  const auth=request.method==='POST'&&incoming.pathname.startsWith('/v1/auth/');for(const binding of [env.API_RATE,...auth?[env.AUTH_RATE]:[]])if(binding&&!((await binding.limit({key})).success))return new Response('Too many requests',{status:429,headers:{'retry-after':'60','cache-control':'no-store'}});
 }
 // Assign path/query separately: an incoming //host must never change the origin.
 const target=new URL(origin);target.pathname=incoming.pathname;target.search=incoming.search;
 const headers=new Headers(request.headers);headers.set('x-tomi-edge',env.TOMI_EDGE_SECRET);
 headers.delete('x-forwarded-for');headers.delete('forwarded');headers.delete('x-real-ip');headers.delete('x-tomi-client-ip');
 const ip=request.headers.get('cf-connecting-ip');if(ip){headers.set('x-forwarded-for',ip);headers.set('x-tomi-client-ip',ip);}
 const upstream=new Request(target,{method:request.method,headers,body:['GET','HEAD'].includes(request.method)?undefined:request.body,redirect:'manual',duplex:'half'});
 return fetcher(upstream);
}
export default {fetch:(request,env)=>forward(request,env)};
