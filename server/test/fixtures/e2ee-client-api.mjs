import {fixture,password} from './platform-api.mjs';
const cleanup=[];const f=await fixture({after:fn=>cleanup.push(fn)});
const a=await f.register('secure_alice'),b=await f.register('secure_bob'),c=await f.register('secure_other');
const created=await f.req(a,'POST','/v1/chats',{userId:b.user.id});if(created.status!==201&&created.status!==200)throw Error('fixture thread');
const login=await f.req(null,'POST','/v1/auth/login',{username:'secure_alice',password});if(login.status!==200)throw Error('fixture second session');const a2=login.data;
process.stdout.write(JSON.stringify({url:f.base,a,a2,b,c,thread:created.data.conversation.id,password})+'\n');
process.stdin.once('data',async()=>{for(const fn of cleanup.reverse())await fn();process.exit(0);});
