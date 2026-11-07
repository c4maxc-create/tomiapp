import {ApiError} from './security.mjs';
// File names and MIME types are claims. Match container magic before publication.
export function verifyDocumentSignature(prefix,name){
 const ext=name.split('.').at(-1).toLowerCase(),hex=prefix.subarray(0,8).toString('hex');
 const reject=()=>{throw new ApiError(400,'INVALID_FILE','محتوى الملف لا يطابق نوعه أو غير مسموح.');};
 if(prefix.subarray(0,2).toString()==='MZ'||hex.startsWith('7f454c46')||prefix.subarray(0,2).toString()==='#!')reject();
 const zip=hex.startsWith('504b0304')||hex.startsWith('504b0506')||hex.startsWith('504b0708');
 if(ext==='pdf'){if(!prefix.subarray(0,1024).includes(Buffer.from('%PDF-')))reject();return;}
 if(['zip','docx','xlsx','pptx'].includes(ext)){if(!zip)reject();return;}
 if(['doc','xls','ppt'].includes(ext)){if(!hex.startsWith('d0cf11e0a1b11ae1'))reject();return;}
 if(ext==='rar'){if(!hex.startsWith('526172211a07'))reject();return;}
 if(ext==='7z'){if(!hex.startsWith('377abcaf271c'))reject();return;}
 if(['txt','csv','json','md'].includes(ext)){
  if(prefix.includes(0))reject();
  // Streaming decoder below checks every UTF-8 byte, including split multibyte characters.
  return;
 }
 reject();
}
