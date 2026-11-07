import {access} from 'node:fs/promises';
import {constants} from 'node:fs';
import {mfaKey} from '../src/mfa.mjs';
import {edgeKey} from '../src/request_security.mjs';
import {backupKey} from '../src/backup_crypto.mjs';
const e=process.env,checks={};
const valid=(fn,value)=>{try{return !!fn(value);}catch{return false;}};
checks.adminMfa=e.TOMI_REQUIRE_ADMIN_MFA==='1'&&valid(mfaKey,e.TOMI_MFA_KEY);
checks.edgeOriginProtection=valid(edgeKey,e.TOMI_EDGE_SECRET);
checks.backupKey=valid(backupKey,e.TOMI_BACKUP_KEY);
checks.backupDatabase=!!e.TOMI_BACKUP_DATABASE_URL;checks.backupDestination=!!e.TOMI_BACKUP_DIRECTORY;
checks.scannerExecutable=false;if(e.TOMI_CLAMSCAN_BINARY)try{await access(e.TOMI_CLAMSCAN_BINARY,constants.X_OK);checks.scannerExecutable=true;}catch{}
checks.privateMediaStorage=!!e.R2_CHAT_BUCKET_NAME&&e.R2_CHAT_BUCKET_NAME!==e.R2_BUCKET_NAME;
// Presence is not proof of provider configuration, successful backups, updated signatures or WAF rules.
console.log(JSON.stringify({checks,note:'Local configuration checks only; no keys, connection strings or media are printed.'},null,2));
if(Object.values(checks).some(v=>!v))process.exitCode=1;
