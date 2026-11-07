// Deploy behind your own proxied hostname. Keep TOMI_EDGE_SECRET in Worker Secrets.
export async function forward(request,env,fetcher=fetch){
 let origin;try{origin=new URL(env.TOMI_ORIGIN);}catch{return new Response('Unavailable',{status:503});}
 if(origin.protocol!=='https:'||origin.username||origin.password||origin.pathname!=='/'||origin.search||origin.hash||!env.TOMI_EDGE_SECRET)return new Response('Unavailable',{status:503});
 const incoming=new URL(request.url);
 if(!env.TOMI_PUBLIC_HOST||incoming.hostname!==env.TOMI_PUBLIC_HOST||incoming.hostname===origin.hostname)return new Response('Forbidden',{status:403});
 // Assign path/query separately: an incoming //host must never change the origin.
 const target=new URL(origin);target.pathname=incoming.pathname;target.search=incoming.search;
 const headers=new Headers(request.headers);headers.set('x-tomi-edge',env.TOMI_EDGE_SECRET);
 headers.delete('x-forwarded-for');headers.delete('forwarded');headers.delete('x-real-ip');headers.delete('x-tomi-client-ip');
 const ip=request.headers.get('cf-connecting-ip');if(ip){headers.set('x-forwarded-for',ip);headers.set('x-tomi-client-ip',ip);}
 const upstream=new Request(target,{method:request.method,headers,body:['GET','HEAD'].includes(request.method)?undefined:request.body,redirect:'manual',duplex:'half'});
 return fetcher(upstream);
}
export default {fetch:(request,env)=>forward(request,env)};
