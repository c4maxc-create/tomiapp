import {decorateRoomUsers} from './room_policy.mjs';
import {ApiError} from './security.mjs';
const zone='Asia/Baghdad',fmt=new Intl.DateTimeFormat('en-GB',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'});
function parts(date){return Object.fromEntries(fmt.formatToParts(date).filter(x=>x.type!=='literal').map(x=>[x.type,Number(x.value)]));}
function instant(y,m,d){
 const target=Date.UTC(y,m-1,d);let t=target;
 for(let i=0;i<3;i++){const p=parts(new Date(t)),shown=Date.UTC(p.year,p.month-1,p.day,p.hour,p.minute,p.second);t+=target-shown;}
 return new Date(t).toISOString();
}
export function rankingPeriod(period='all',at=new Date()){
 if(!['daily','weekly','all'].includes(period))throw new ApiError(400,'VALIDATION','اختر الترتيب اليومي أو الأسبوعي أو الكلي.');
 const p=parts(at),calendar=new Date(Date.UTC(p.year,p.month-1,p.day));
 if(period==='weekly')calendar.setUTCDate(calendar.getUTCDate()-((calendar.getUTCDay()+2)%7));
 const from=period==='all'?null:instant(calendar.getUTCFullYear(),calendar.getUTCMonth()+1,calendar.getUTCDate());
 calendar.setUTCDate(calendar.getUTCDate()+(period==='weekly'?7:1));
 const until=period==='all'?null:instant(calendar.getUTCFullYear(),calendar.getUTCMonth()+1,calendar.getUTCDate());
 return {period,timeZone:zone,from,until,serverTime:at.toISOString()};
}
export async function giftRanking(db,viewer,usersByIds,{roomId=null,period='all',at=new Date()}={}){
 const window=rankingPeriod(period,at),conditions=["NOT EXISTS(SELECT 1 FROM tomi_account_restrictions a WHERE a.user_id=g.sender_id AND a.suspended=1)"],values=[];
 if(roomId){conditions.push('g.room_id=?');values.push(roomId);}
 if(window.from){conditions.push('g.created_at>=? AND g.created_at<?');values.push(window.from,window.until);}
 conditions.push('NOT EXISTS(SELECT 1 FROM tomi_user_blocks b WHERE (b.blocker_id=? AND b.blocked_id=g.sender_id) OR (b.blocked_id=? AND b.blocker_id=g.sender_id))');values.push(viewer,viewer);
 const rows=(await db.query('SELECT g.sender_id,SUM(g.total) AS points,COUNT(*) AS gifts,SUM(CASE WHEN g.sender_id=g.recipient_id THEN g.total ELSE 0 END) AS self_points FROM tomi_room_all_gifts g WHERE '+conditions.join(' AND ')+' GROUP BY g.sender_id ORDER BY SUM(g.total) DESC,g.sender_id LIMIT 100',values)).rows;
 const own=(await db.query('SELECT COALESCE(SUM(g.total),0) AS points,COALESCE(SUM(CASE WHEN g.sender_id=g.recipient_id THEN g.total ELSE 0 END),0) AS self_points FROM tomi_room_all_gifts g WHERE '+conditions.join(' AND ')+' AND g.sender_id=?',[...values,viewer])).rows[0];
 const users=await usersByIds(rows.map(r=>r.sender_id),viewer,db);
 if(roomId)await decorateRoomUsers(db,users);
 return {...window,myPoints:Number(own.points),mySelfPoints:Number(own.self_points),leaders:rows.map((r,i)=>({rank:i+1,user:users.get(r.sender_id),points:Number(r.points),gifts:Number(r.gifts),selfPoints:Number(r.self_points)}))};
}
