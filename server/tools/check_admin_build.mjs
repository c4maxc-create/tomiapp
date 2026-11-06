import {mkdtemp,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
const directory=await mkdtemp(join(tmpdir(),'tomi-admin-build-'));
try{
 const result=spawnSync(process.execPath,['node_modules/typescript/bin/tsc','-p','tsconfig.admin.json','--outDir',directory],{stdio:'inherit'});
 if(result.status!==0)throw Error('TypeScript admin compilation failed.');
 const generated=await readFile(join(directory,'dashboard.js')),tracked=await readFile(new URL('../public/admin/dashboard.js',import.meta.url));
 if(!generated.equals(tracked))throw Error('Admin browser asset is stale; run npm run build:admin.');
 console.log('PASS: TypeScript administration asset matches its checked source.');
}finally{await rm(directory,{recursive:true,force:true});}
