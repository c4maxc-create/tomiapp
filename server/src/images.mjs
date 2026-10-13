import { ApiError } from './security.mjs';
export const maxImageBytes=10*1024*1024;
export const imageTypes={'image/jpeg':'jpg','image/png':'png','image/webp':'webp','image/gif':'gif'};
export function imageDimensions(b,type) {
 let width,height;
 if(type==='image/png' && b.length>=33 && b.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])) && b.readUInt32BE(8)===13 && b.toString('ascii',12,16)==='IHDR') {
  width=b.readUInt32BE(16);height=b.readUInt32BE(20);
 } else if(type==='image/gif' && b.length>=13 && /^GIF8[79]a$/.test(b.toString('ascii',0,6))) {
  width=b.readUInt16LE(6);height=b.readUInt16LE(8);
 } else if(type==='image/webp' && b.length>=30 && b.toString('ascii',0,4)==='RIFF' && b.toString('ascii',8,12)==='WEBP') {
  const kind=b.toString('ascii',12,16);
  if(kind==='VP8X'){width=1+b.readUIntLE(24,3);height=1+b.readUIntLE(27,3);}
  else if(kind==='VP8 ' && b[23]===157 && b[24]===1 && b[25]===42){width=b.readUInt16LE(26)&0x3fff;height=b.readUInt16LE(28)&0x3fff;}
  else if(kind==='VP8L' && b[20]===47){const p=b.readUInt32LE(21);width=(p&0x3fff)+1;height=((p>>>14)&0x3fff)+1;}
 } else if(type==='image/jpeg' && b[0]===255 && b[1]===216) {
  let p=2;const frames=new Set([192,193,194,195,197,198,199,201,202,203,205,206,207]);
  while(p+4<b.length){
   if(b[p++]!==255)break;while(b[p]===255)p++;
   const marker=b[p++];if(marker===218||marker===217)break;
   if(marker===1||(marker>=208&&marker<=215))continue;
   if(p+2>b.length)break;const length=b.readUInt16BE(p);
   if(length<2||p+length>b.length)break;
   if(frames.has(marker)&&length>=8){height=b.readUInt16BE(p+3);width=b.readUInt16BE(p+5);break;}
   p+=length;
  }
 }
 if(!width||!height||width>12000||height>12000||width*height>36000000)throw new ApiError(400,'INVALID_IMAGE','الصورة غير مدعومة أو أبعادها كبيرة؛ اختَر صورة ثانية.');
 return {width,height};
}
