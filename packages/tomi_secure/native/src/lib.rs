//! Small Apache-2.0 FFI adapter to Matrix.org vodozemac. No private keys cross the server boundary.
use aes_gcm::{aead::{Aead, KeyInit, Payload}, Aes256Gcm, Nonce};
use argon2::{Algorithm, Argon2, Params, Version};
use base64::{engine::general_purpose::{STANDARD,STANDARD_NO_PAD}, Engine};
use serde_json::{json, Value};
use std::{ffi::{c_char, CString}, panic::{catch_unwind, AssertUnwindSafe}};
use vodozemac::{olm::{Account, AccountPickle, Session, SessionPickle, SessionConfig, OlmMessage}, Curve25519PublicKey};
use zeroize::{Zeroizing,Zeroize};
type Result<T> = std::result::Result<T, String>;
fn text<'a>(v: &'a Value, name: &str) -> Result<&'a str> {v.get(name).and_then(Value::as_str).ok_or_else(||"BAD_INPUT".into())}
fn decode(s:&str)->Result<Vec<u8>>{STANDARD.decode(s).or_else(|_|STANDARD_NO_PAD.decode(s)).map_err(|_|"BAD_ENCODING".into())}
fn key(v:&Value)->Result<Zeroizing<[u8;32]>>{let b=decode(text(v,"key")?)?;Ok(Zeroizing::new(b.try_into().map_err(|_|"BAD_KEY")?))}
fn random<const N:usize>()->Result<[u8;N]>{let mut b=[0;N];getrandom::fill(&mut b).map_err(|_|"RANDOM_UNAVAILABLE")?;Ok(b)}
fn account(v:&Value,k:&[u8;32])->Result<Account>{Ok(Account::from_pickle(AccountPickle::from_encrypted(text(v,"account")?,k).map_err(|_|"BAD_PICKLE")?))}
fn session(pickle:&str,k:&[u8;32])->Result<Session>{Ok(Session::from_pickle(SessionPickle::from_encrypted(pickle,k).map_err(|_|"BAD_PICKLE")?))}
fn crypt(data:&[u8],k:&[u8;32],aad:&str,encrypt:bool)->Result<Vec<u8>>{
 let cipher=Aes256Gcm::new_from_slice(k).map_err(|_|"BAD_KEY")?;
 if encrypt{let iv=random::<12>()?;let body=cipher.encrypt(Nonce::from_slice(&iv),Payload{msg:data,aad:aad.as_bytes()}).map_err(|_|"ENCRYPT_FAILED")?;Ok([iv.to_vec(),body].concat())}
 else{if data.len()<28{return Err("BAD_CIPHERTEXT".into())}cipher.decrypt(Nonce::from_slice(&data[..12]),Payload{msg:&data[12..],aad:aad.as_bytes()}).map_err(|_|"AUTHENTICATION_FAILED".into())}
}
fn run(v:Value)->Result<Value>{
 let op=text(&v,"op")?;
 if op=="verify"{let key=vodozemac::Ed25519PublicKey::from_base64(text(&v,"publicKey")?).map_err(|_|"BAD_SIGNING_KEY")?;let signature=vodozemac::Ed25519Signature::from_base64(text(&v,"signature")?).map_err(|_|"BAD_SIGNATURE")?;key.verify(text(&v,"data")?.as_bytes(),&signature).map_err(|_|"BAD_SIGNATURE")?;return Ok(json!({"valid":true}))}
 if op=="random"{return Ok(json!({"key":STANDARD.encode(random::<32>()?)}))}
 if op=="backup_export"||op=="backup_import"{
  let password=text(&v,"password")?;if password.chars().count()<20||password.len()>1024{return Err("BACKUP_PASSPHRASE".into())}
  let salt=if op=="backup_export"{random::<16>()?.to_vec()}else{decode(text(&v,"salt")?)?};if salt.len()!=16{return Err("BAD_SALT".into())}
  let params=Params::new(65536,3,1,Some(32)).map_err(|_|"KDF_FAILED")?;let mut k=Zeroizing::new([0;32]);
  Argon2::new(Algorithm::Argon2id,Version::V0x13,params).hash_password_into(password.as_bytes(),&salt,&mut *k).map_err(|_|"KDF_FAILED")?;
  let bytes=decode(text(&v,"data")?)?;let result=crypt(&bytes,&k,text(&v,"aad")?,op=="backup_export")?;
  return Ok(json!({"salt":STANDARD.encode(salt),"data":STANDARD.encode(result)}))
 }
 if op=="save_state"{
  use std::io::Write;
  let output=std::path::Path::new(text(&v,"path")?);if !output.is_absolute()||output.file_name().and_then(|s|s.to_str())!=Some("state.enc"){return Err("STATE_PATH".into())}
  let parent=output.parent().ok_or("STATE_PATH")?;let temp=parent.join(format!("secure-state-{}.tmp",STANDARD_NO_PAD.encode(random::<16>()?).replace('/',"_").replace('+',"-")));
  let mut options=std::fs::OpenOptions::new();options.write(true).create_new(true);#[cfg(unix)]{use std::os::unix::fs::OpenOptionsExt;options.mode(0o600);}
  let result=(||->std::io::Result<()>{let mut file=options.open(&temp)?;file.write_all(text(&v,"data").map_err(|_|std::io::Error::other("invalid state"))?.as_bytes())?;file.sync_all()?;std::fs::rename(&temp,output)?;std::fs::File::open(parent)?.sync_all()?;Ok(())})();
  if result.is_err(){let _=std::fs::remove_file(&temp);return Err("STATE_WRITE".into())}return Ok(json!({"saved":true}))
 }
 let k=key(&v)?;
 if op=="seal_file"||op=="open_file"{
  use std::io::{Read,Write};
  let source=text(&v,"source")?;let output=text(&v,"output")?;
  if !std::path::Path::new(source).is_absolute()||!std::path::Path::new(output).is_absolute(){return Err("FILE_PATH".into())}
  let mut bytes=Zeroizing::new(Vec::new());std::fs::File::open(source).map_err(|_|"FILE_OPEN")?.take(25*1024*1024+1).read_to_end(&mut bytes).map_err(|_|"FILE_READ")?;
  if bytes.len()>25*1024*1024{return Err("FILE_LIMIT".into())}
  let data=if op=="seal_file"{let sealed=crypt(&bytes,&k,text(&v,"aad")?,true)?;[b"TOMIE2E1".to_vec(),sealed].concat()}else{if !bytes.starts_with(b"TOMIE2E1"){return Err("FILE_FORMAT".into())}crypt(&bytes[8..],&k,text(&v,"aad")?,false)?};
  let data=Zeroizing::new(data);if data.len()>25*1024*1024{return Err("FILE_LIMIT".into())}
  let mut options=std::fs::OpenOptions::new();options.write(true).create_new(true);
  #[cfg(unix)]{use std::os::unix::fs::OpenOptionsExt;options.mode(0o600);}
  let mut file=options.open(output).map_err(|_|"FILE_EXISTS")?;if file.write_all(&data).and_then(|_|file.sync_all()).is_err(){let _=std::fs::remove_file(output);return Err("FILE_WRITE".into())}
  return Ok(json!({"bytes":data.len()}))
 }
 if op=="seal"||op=="open"{let data=decode(text(&v,"data")?)?;let result=crypt(&data,&k,text(&v,"aad")?,op=="seal")?;return Ok(json!({"data":STANDARD.encode(result)}))}
 if op=="new"||op=="prekeys"{
  let mut a=if op=="new"{Account::new()}else{account(&v,&k)?};if a.stored_one_time_key_count()<64{a.generate_one_time_keys(32);}if op=="new"{a.generate_fallback_key();}
  let uid=text(&v,"user")?;let device=text(&v,"device")?;
  let keys:Vec<Value>=a.one_time_keys().into_iter().map(|(id,public)|{let id=id.to_base64();let public=public.to_base64();let content=format!("TOMI_PREKEY_V1|{uid}|{device}|{id}|{public}");json!({"id":id,"key":public,"signature":a.sign(content).to_base64()})}).collect();
  let fallback=a.fallback_key().into_iter().next().map(|(id,public)|{let id=id.to_base64();let public=public.to_base64();let content=format!("TOMI_PREKEY_V1|{uid}|{device}|{id}|{public}");json!({"id":id,"key":public,"signature":a.sign(content).to_base64()})});
  a.mark_keys_as_published();return Ok(json!({"fallback":fallback,"account":a.pickle().encrypt(&k),"signingKey":a.ed25519_key().to_base64(),"identityKey":a.curve25519_key().to_base64(),"prekeys":keys}))
 }
 if op=="sign"{let a=account(&v,&k)?;return Ok(json!({"signature":a.sign(text(&v,"data")?).to_base64()}))}
 if op=="encrypt"{
  let a=account(&v,&k)?;
  let mut s=if let Some(p)=v.get("session").and_then(Value::as_str){session(p,&k)?}else{a.create_outbound_session(SessionConfig::version_1(),Curve25519PublicKey::from_base64(text(&v,"identity")?).map_err(|_|"BAD_IDENTITY")?,Curve25519PublicKey::from_base64(text(&v,"prekey")?).map_err(|_|"BAD_PREKEY")?).map_err(|_|"SESSION_FAILED")?};
  let message=s.encrypt(text(&v,"plaintext")?).map_err(|_|"ENCRYPT_FAILED")?;
  return Ok(json!({"session":s.pickle().encrypt(&k),"sessionId":s.session_id(),"message":message}))
 }
 if op=="decrypt"{
  let mut a=account(&v,&k)?;let message:OlmMessage=serde_json::from_value(v.get("message").ok_or("BAD_INPUT")?.clone()).map_err(|_|"BAD_MESSAGE")?;
  let sessions=v.get("sessions").and_then(Value::as_array).ok_or("BAD_INPUT")?;if sessions.len()>8{return Err("TOO_MANY_SESSIONS".into())}
  for (i,p) in sessions.iter().enumerate(){let mut s=session(p.as_str().ok_or("BAD_INPUT")?,&k)?;if let Ok(plaintext)=s.decrypt(&message){return Ok(json!({"plaintext":String::from_utf8(plaintext).map_err(|_|"BAD_UTF8")?,"session":s.pickle().encrypt(&k),"sessionId":s.session_id(),"index":i,"account":a.pickle().encrypt(&k)}))}}
  if let OlmMessage::PreKey(prekey)=message{let result=a.create_inbound_session(SessionConfig::version_1(),Curve25519PublicKey::from_base64(text(&v,"identity")?).map_err(|_|"BAD_IDENTITY")?,&prekey).map_err(|_|"DECRYPT_FAILED")?;return Ok(json!({"plaintext":String::from_utf8(result.plaintext).map_err(|_|"BAD_UTF8")?,"session":result.session.pickle().encrypt(&k),"sessionId":result.session.session_id(),"index":-1,"account":a.pickle().encrypt(&k)}))}
  return Err("DECRYPT_FAILED".into())
 }
 Err("BAD_OPERATION".into())
}
/// Inputs and outputs are bounded JSON. Errors never include plaintext, keys or library panic values.
#[no_mangle]
pub unsafe extern "C" fn tomi_secure_call(input:*const u8,length:usize)->*mut c_char{
 let result=catch_unwind(AssertUnwindSafe(||{if input.is_null()||length>64*1024*1024{return Err("INPUT_LIMIT".into())}let v:Value=serde_json::from_slice(std::slice::from_raw_parts(input,length)).map_err(|_|"BAD_JSON")?;run(v)}));
 let value=match result{Ok(Ok(v))=>json!({"ok":v}),Ok(Err(e))=>json!({"error":e}),Err(_)=>json!({"error":"CRYPTO_FAILED"})};
 CString::new(value.to_string()).unwrap_or_default().into_raw()
}
#[no_mangle]
pub unsafe extern "C" fn tomi_secure_free(value:*mut c_char){if !value.is_null(){let mut bytes=CString::from_raw(value).into_bytes_with_nul();bytes.zeroize();}}
#[cfg(test)]
mod tests{
 use super::*;
 fn invoke(v:Value)->Value{run(v).unwrap()}
 #[test]fn olm_roundtrip_out_of_order_tamper_replay_and_pickle(){
  let ka=STANDARD.encode(random::<32>().unwrap());let kb=STANDARD.encode(random::<32>().unwrap());let a=invoke(json!({"op":"new","key":ka,"user":"alice","device":"a"}));let b=invoke(json!({"op":"new","key":kb,"user":"bob","device":"b"}));
  let first=invoke(json!({"op":"encrypt","key":ka,"account":a["account"],"identity":b["identityKey"],"prekey":b["prekeys"][0]["key"],"plaintext":"hello"}));
  let received=invoke(json!({"op":"decrypt","key":kb,"account":b["account"],"identity":a["identityKey"],"sessions":[],"message":first["message"]}));assert_eq!(received["plaintext"],"hello");
  let reply=invoke(json!({"op":"encrypt","key":kb,"account":received["account"],"session":received["session"],"plaintext":"reply"}));
  let answer=invoke(json!({"op":"decrypt","key":ka,"account":a["account"],"identity":b["identityKey"],"sessions":[first["session"]],"message":reply["message"]}));assert_eq!(answer["plaintext"],"reply");
  let second=invoke(json!({"op":"encrypt","key":ka,"account":a["account"],"session":answer["session"],"plaintext":"second"}));
  let third=invoke(json!({"op":"encrypt","key":ka,"account":a["account"],"session":second["session"],"plaintext":"third"}));
  let r3=invoke(json!({"op":"decrypt","key":kb,"account":received["account"],"identity":a["identityKey"],"sessions":[reply["session"]],"message":third["message"]}));
  let r2=invoke(json!({"op":"decrypt","key":kb,"account":r3["account"],"identity":a["identityKey"],"sessions":[r3["session"]],"message":second["message"]}));assert_eq!(r2["plaintext"],"second");
  assert!(run(json!({"op":"decrypt","key":kb,"account":r2["account"],"identity":a["identityKey"],"sessions":[r2["session"]],"message":second["message"]})).is_err());
  let mut tampered=third["message"].clone();tampered["body"]=json!("AAAA");assert!(run(json!({"op":"decrypt","key":kb,"account":r2["account"],"identity":a["identityKey"],"sessions":[r2["session"]],"message":tampered})).is_err());
  assert!(run(json!({"op":"sign","key":kb,"account":a["account"],"data":"x"})).is_err());
 }
 #[test]fn aes_authenticates_data_and_context(){let k=STANDARD.encode(random::<32>().unwrap());let encrypted=invoke(json!({"op":"seal","key":k,"data":STANDARD.encode(b"private file"),"aad":"file1"}));let d=invoke(json!({"op":"open","key":k,"data":encrypted["data"],"aad":"file1"}));assert_eq!(decode(d["data"].as_str().unwrap()).unwrap(),b"private file");assert!(run(json!({"op":"open","key":k,"data":encrypted["data"],"aad":"file2"})).is_err());}
 #[test]fn backup_requires_passphrase_and_authentication(){let p="long independent backup passphrase 42";let a=invoke(json!({"op":"backup_export","password":p,"data":STANDARD.encode(b"private history"),"aad":"user1"}));let d=invoke(json!({"op":"backup_import","password":p,"salt":a["salt"],"data":a["data"],"aad":"user1"}));assert_eq!(decode(d["data"].as_str().unwrap()).unwrap(),b"private history");assert!(run(json!({"op":"backup_import","password":"a different long passphrase","salt":a["salt"],"data":a["data"],"aad":"user1"})).is_err());}
 #[test]fn private_files_and_atomic_state_are_authenticated_and_bounded(){
  let dir=std::env::temp_dir().join(format!("tomi-native-{}",STANDARD_NO_PAD.encode(random::<16>().unwrap()).replace('/',"_").replace('+',"-")));std::fs::create_dir(&dir).unwrap();
  let source=dir.join("source" );let sealed=dir.join("sealed");let plain=dir.join("plain");let state=dir.join("state.enc");std::fs::write(&source,b"private attachment").unwrap();let key=STANDARD.encode(random::<32>().unwrap());
  invoke(json!({"op":"seal_file","key":key,"aad":"thread/request","source":source,"output":sealed}));assert!(!std::fs::read(&sealed).unwrap().windows(18).any(|x|x==b"private attachment"));
  assert!(run(json!({"op":"open_file","key":key,"aad":"different","source":sealed,"output":plain})).is_err());assert!(!plain.exists());
  invoke(json!({"op":"open_file","key":key,"aad":"thread/request","source":sealed,"output":plain}));assert_eq!(std::fs::read(&plain).unwrap(),b"private attachment");assert!(run(json!({"op":"open_file","key":key,"aad":"thread/request","source":sealed,"output":plain})).is_err());
  invoke(json!({"op":"save_state","path":state,"data":"encrypted1"}));invoke(json!({"op":"save_state","path":state,"data":"encrypted2"}));assert_eq!(std::fs::read_to_string(&state).unwrap(),"encrypted2");
  #[cfg(unix)] {use std::os::unix::fs::PermissionsExt;assert_eq!(std::fs::metadata(&state).unwrap().permissions().mode() & 0o777,0o600);}
  assert_eq!(std::fs::read_dir(&dir).unwrap().count(),4);std::fs::remove_dir_all(dir).unwrap();
 }

}
