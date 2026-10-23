import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs/promises';import path from 'node:path';import os from 'node:os';import {spawn,spawnSync} from 'node:child_process';import {fileURLToPath} from 'node:url';
const windows=process.platform==='win32';
test('Windows guard distinguishes an entry script from an unrelated data argument',{skip:!windows},async()=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'clawbot-guard-')),app=path.join(root,'an app'),outside=path.join(root,'outside.mjs'),entry=path.join(app,'entry.mjs'),guard=path.join(root,'SetupGuard.exe'),children=[];
 try{
  await fs.mkdir(app);const script='import fs from "node:fs";fs.writeFileSync(process.argv[2],"ready");setInterval(()=>{},1000);';await fs.writeFile(outside,script);await fs.writeFile(entry,script);
  const source=fileURLToPath(new URL('../installer/SetupGuard.cs',import.meta.url)),compiler=path.join(process.env.SystemRoot,'Microsoft.NET/Framework64/v4.0.30319/csc.exe');
  const build=spawnSync(compiler,['/nologo','/reference:System.Management.dll','/out:'+guard,source],{encoding:'utf8',windowsHide:true});assert.equal(build.status,0,build.stdout+build.stderr);
  const start=async(exe,args,ready)=>{const child=spawn(exe,args,{windowsHide:true,stdio:'ignore'});children.push(child);for(let i=0;i<100;i++){if(await fs.access(ready).then(()=>true,()=>false))return child;await new Promise(r=>setTimeout(r,30));}throw Error('fixture did not start');};
  const inspect=()=>{const result=spawnSync(guard,[app,'--report'],{encoding:'utf8',windowsHide:true});return {code:result.status,...JSON.parse(result.stdout)};};
  const unrelatedReady=path.join(root,'unrelated-ready');await start(process.execPath,[outside,unrelatedReady,path.join(app,'outputs','document.pdf')],unrelatedReady);
  assert.equal(inspect().code,0,'a data argument must not own the installation');
  const entryReady=path.join(root,'entry-ready'),owned=await start(process.execPath,[entry,entryReady],entryReady);const blocked=inspect();assert.equal(blocked.code,42);assert.ok(blocked.processes.some(x=>x.pid===owned.pid&&x.name==='node.exe'));assert.ok(!JSON.stringify(blocked).includes('document.pdf'));
  owned.kill();await new Promise(r=>owned.once('exit',r));assert.equal(inspect().code,0);
  const runtime=path.join(app,'node.exe');await fs.copyFile(process.execPath,runtime);const runtimeReady=path.join(root,'runtime-ready'),runtimeChild=await start(runtime,[outside,runtimeReady],runtimeReady);assert.ok(inspect().processes.some(x=>x.pid===runtimeChild.pid));
 }finally{for(const child of children)if(child.exitCode===null&&child.signalCode===null){child.kill();await new Promise(r=>child.once('exit',r));}await fs.rm(root,{recursive:true,force:true,maxRetries:10,retryDelay:100});}
});
