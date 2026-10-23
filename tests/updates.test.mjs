import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs/promises';import os from 'node:os';import path from 'node:path';import {createHash} from 'node:crypto';import {spawnSync} from 'node:child_process';import {fileURLToPath} from 'node:url';
import {versionParts,newer,selectRelease,checkUpdate,downloadUpdate,verifyInstaller,LATEST_URL} from '../src/updates.mjs';
const temporary=await fs.mkdtemp(path.join(os.tmpdir(),'clawbot-updates-'));test.after(()=>fs.rm(temporary,{recursive:true,force:true,maxRetries:10,retryDelay:100}));
const payload=Buffer.from('test installer data; never executable'),digest=createHash('sha256').update(payload).digest('hex');
function release(version='1.4.0'){const name='ClawBot-Instance-Manager-Setup-'+version+'-windows-x64.exe';return {tag_name:'v'+version,html_url:'https://github.com/SakuraEdge/wechat-assistant/releases/tag/v'+version,draft:false,prerelease:false,published_at:'2026-10-22T00:00:00Z',assets:[{name,state:'uploaded',size:payload.length,digest:'sha256:'+digest,browser_download_url:'https://github.com/SakuraEdge/wechat-assistant/releases/download/v'+version+'/'+name}]};}
const selected=()=>selectRelease(release(),'1.3.0');
test('only stable strictly newer versions are updates; versions compare numerically',()=>{
 assert.equal(newer('1.10.0','1.9.0'),true);assert.equal(newer('v1.2.0','1.3.0'),false);assert.equal(selectRelease(release('1.3.0'),'1.3.0').available,false);assert.equal(selected().available,true);
 for(const bad of ['1.2','01.2.3','1.2.3-beta','1.2.3+test','1.2.3/../../','9999999999.0.0'])assert.throws(()=>versionParts(bad),/UPDATE_VERSION_INVALID/);
 for(const mutate of [r=>r.draft=true,r=>r.prerelease=true,r=>r.html_url='https://example.com/',r=>r.published_at=null]){const r=release();mutate(r);assert.throws(()=>selectRelease(r,'1.3.0'),/UPDATE_RELEASE_INVALID/);}
});
test('only a unique installer with matching repository, tag, size and SHA256 can be selected',()=>{
 for(const mutate of [r=>r.assets=[],r=>r.assets.push(r.assets[0]),r=>r.assets[0].digest=null,r=>r.assets[0].size=300*1024*1024,r=>r.assets[0].browser_download_url='https://github.com/elsewhere/bot/releases/download/v1.4.0/a.exe']){const r=release();mutate(r);assert.throws(()=>selectRelease(r,'1.3.0'),/UPDATE_(?:ASSET|URL)/);}
});
test('update check uses fixed public unauthenticated endpoint and distinguishes offline/rate-limit/no-release',async()=>{
 const calls=[];const value=await checkUpdate('1.3.0',{fetchImpl:async(url,options)=>{calls.push({url,options});return Response.json(release());}});assert.equal(value.available,true);assert.equal(calls.length,1);assert.equal(calls[0].url,LATEST_URL);assert.equal(calls[0].options.headers.Authorization,undefined);assert.equal(calls[0].options.headers.Cookie,undefined);
 assert.equal((await checkUpdate('1.3.0',{fetchImpl:async()=>new Response('',{status:404})})).reason,'NO_PUBLISHED_RELEASE');await assert.rejects(checkUpdate('1.3.0',{fetchImpl:async()=>new Response('',{status:429})}),/UPDATE_RATE_LIMITED/);await assert.rejects(checkUpdate('1.3.0',{fetchImpl:async()=>{throw Error('offline');}}),/UPDATE_NETWORK_FAILED/);
});
test('download follows only GitHub asset redirects, verifies bytes, and reuses verified cache',async()=>{
 const root=path.join(temporary,'download');let calls=0;const value=await downloadUpdate(selected(),root,{fetchImpl:async(url)=>{calls++;return calls===1?new Response(null,{status:302,headers:{location:'https://release-assets.githubusercontent.com/fixture'}}):new Response(payload);}});
 assert.equal(calls,2);assert.deepEqual(await fs.readFile(value.file),payload);assert.equal(await verifyInstaller(value.file,selected().asset,root),value.file);
 await downloadUpdate(selected(),root,{fetchImpl:async()=>{throw Error('cache must avoid network');}});
 await fs.writeFile(value.file,Buffer.alloc(payload.length));await assert.rejects(verifyInstaller(value.file,selected().asset,root),/UPDATE_HASH_MISMATCH/);
});
test('unsafe redirects, size/hash mismatch and interrupted streams cannot produce an installable file',async()=>{
 const cases=[['redirect',async()=>new Response(null,{status:302,headers:{location:'https://attacker.example/a.exe'}}),/UPDATE_URL_REJECTED/],['length',async()=>new Response(payload,{headers:{'content-length':'1'}}),/UPDATE_SIZE_MISMATCH/],['hash',async()=>new Response(Buffer.alloc(payload.length)),/UPDATE_HASH_MISMATCH/],['oversize',async()=>new Response(Buffer.alloc(payload.length+1)),/UPDATE_SIZE_MISMATCH/],['truncated',async()=>new Response(payload.subarray(0,3)),/UPDATE_HASH_MISMATCH/],['loop',async()=>new Response(null,{status:302,headers:{location:'https://github.com/loop'}}),/UPDATE_REDIRECT_LIMIT/]];
 for(const [name,fetchImpl,expected]of cases){const root=path.join(temporary,name);await assert.rejects(downloadUpdate(selected(),root,{fetchImpl}),expected);assert.deepEqual(await fs.readdir(path.join(root,'1.4.0')),[]);}
});
test('download refuses linked version directories and linked installer files',async()=>{
 const root=path.join(temporary,'links'),outside=path.join(temporary,'outside');await fs.mkdir(root);await fs.mkdir(outside);await fs.symlink(outside,path.join(root,'1.4.0'),process.platform==='win32'?'junction':'dir');await assert.rejects(downloadUpdate(selected(),root,{fetchImpl:async()=>new Response(payload)}),/UPDATE_PATH_REJECTED/);
});
test('download reports actual bytes and verification before reaching 100 percent',async()=>{
 const values=[],root=path.join(temporary,'progress');let offset=0,time=0;
 const stream=new ReadableStream({pull(controller){if(offset===payload.length){controller.close();return;}const end=Math.min(offset+5,payload.length);controller.enqueue(payload.subarray(offset,end));offset=end;time+=250;}});
 const result=await downloadUpdate(selected(),root,{now:()=>time,fetchImpl:async()=>new Response(stream),onProgress:async value=>{values.push(value);if(value.phase==='ready')assert.equal((await fs.stat(path.join(root,'1.4.0',selected().asset.name))).size,payload.length);else assert.ok(value.percent<100);}});
 assert.equal(values[0].phase,'connecting');assert.equal(values.at(-2).phase,'verifying');assert.equal(values.at(-1).phase,'ready');assert.equal(values.at(-1).percent,100);assert.equal(values.at(-1).received_bytes,result.bytes);
 assert.ok(values.some(x=>x.phase==='downloading'&&x.received_bytes>0&&x.received_bytes<payload.length));assert.ok(values.every((x,i)=>!i||x.received_bytes>=values[i-1].received_bytes));
 const cached=[];await downloadUpdate(selected(),root,{fetchImpl:async()=>{throw Error('unexpected network');},onProgress:async x=>cached.push(x)});assert.equal(cached.at(-1).phase,'ready');
});
test('failed or interrupted downloads never report verified completion',async()=>{
 for(const name of ['bad-hash','broken-stream']){
  const values=[],root=path.join(temporary,name);
  const body=name==='bad-hash'?new Response(Buffer.alloc(payload.length)):new Response(new ReadableStream({start(c){c.enqueue(payload.subarray(0,5));c.error(Error('interrupted'));}}));
  await assert.rejects(downloadUpdate(selected(),root,{fetchImpl:async()=>body,onProgress:async x=>values.push(x)}));
  assert.ok(!values.some(x=>x.phase==='ready'||x.percent===100));assert.deepEqual(await fs.readdir(path.join(root,'1.4.0')),[]);
 }
});
test('GitHub API rate limits fall back to the fixed public release with repository checks',async()=>{
 const calls=[];const value=await checkUpdate('1.3.0',{fetchImpl:async(url,options)=>{
  calls.push({url,method:options.method||'GET'});
  if(url===LATEST_URL)return new Response('',{status:403});
  if(url.endsWith('/releases/latest'))return new Response(null,{status:302,headers:{location:release().html_url}});
  if(url.endsWith('SHA256SUMS.txt'))return new Response(digest+'  '+release().assets[0].name+'\n');
  assert.equal(options.method,'HEAD');return new Response(null,{headers:{'content-length':String(payload.length)}});
 }});assert.equal(value.available,true);assert.equal(value.source,'github-public-release');assert.equal(value.asset.sha256,digest);assert.equal(calls.length,4);
 await assert.rejects(checkUpdate('1.3.0',{fetchImpl:async url=>url===LATEST_URL?new Response('',{status:429}):new Response(null,{status:302,headers:{location:'https://github.com/other/repo/releases/tag/v1.4.0'}})}),/UPDATE_RELEASE_INVALID/);
});
test('Windows install handoff independently rejects changed installer bytes and never launches during SelfTest',{skip:process.platform!=='win32'},async()=>{
 const root=path.join(temporary,'handoff');const result=await downloadUpdate(selected(),root,{fetchImpl:async()=>new Response(payload)});const job=path.join(root,'job.json');await fs.writeFile(job,JSON.stringify({download_root:await fs.realpath(root),installer:result.file,bytes:payload.length,sha256:digest}));
 const script=fileURLToPath(new URL('../src/ApplyUpdate.ps1',import.meta.url));const invoke=()=>spawnSync('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',script,'-JobFile',job,'-SelfTest'],{encoding:'utf8',windowsHide:true});
 const valid=invoke();assert.equal(valid.status,0,valid.stdout+valid.stderr);await fs.writeFile(result.file,Buffer.alloc(payload.length));const changed=invoke();assert.equal(changed.status,1);assert.match(changed.stdout,/UPDATE_HASH_MISMATCH/);
});
test('hidden Windows helper executes and survives the controller exiting',{skip:process.platform!=='win32'},async()=>{
 const root=path.join(temporary,"helper lifetime's folder");await fs.mkdir(root);const script=path.join(root,'Probe.ps1'),parent=path.join(root,'parent.mjs'),done=path.join(root,'parent-exited'),marker=path.join(root,'helper-survived');
 await fs.writeFile(script,'param([string]$JobFile)\n[IO.File]::WriteAllText($JobFile+".ready","ready");for($i=0;$i -lt 100;$i++){if([IO.File]::Exists($env:CLAWBOT_TEST_PARENT_EXIT)){[IO.File]::WriteAllText($env:CLAWBOT_TEST_HELPER_MARKER,"survived");exit 0};Start-Sleep -Milliseconds 50};exit 2');
 await fs.writeFile(parent,'import fs from "node:fs/promises";import {launchUpdateHelper} from '+JSON.stringify(new URL('../src/update-launch.mjs',import.meta.url).href)+';const job='+JSON.stringify(done)+';const child=launchUpdateHelper('+JSON.stringify(script)+',job,'+JSON.stringify(root)+');for(let i=0;i<100;i++){if(await fs.access(job+".ready").then(()=>true,()=>false))break;if(i===99)throw Error("helper never ready");await new Promise(r=>setTimeout(r,50));}child.unref();');
 const result=spawnSync(process.execPath,[parent],{env:{...process.env,CLAWBOT_TEST_PARENT_EXIT:done,CLAWBOT_TEST_HELPER_MARKER:marker},encoding:'utf8',windowsHide:true,timeout:10000});assert.equal(result.status,0,result.stderr);await fs.writeFile(done,'exited');
 for(let i=0;i<80;i++){if(await fs.access(marker).then(()=>true,()=>false))break;await new Promise(r=>setTimeout(r,50));}
 assert.equal(await fs.readFile(marker,'utf8'),'survived');
});
test('Windows handoff waits for manager exit, executes the verified installer and records its result',{skip:process.platform!=='win32'},async()=>{
 const root=path.join(temporary,'full-handoff');await fs.mkdir(root);const app=path.join(root,'app');await fs.mkdir(app);const jobs=path.join(root,'jobs');await fs.mkdir(jobs);
 const source=path.join(root,'Fixture.cs');await fs.writeFile(source,'using System;using System.IO;static class Fixture{[STAThread]static void Main(string[] args){File.AppendAllText(Environment.GetEnvironmentVariable("CLAWBOT_TEST_MARKER"),string.Join("|",args)+Environment.NewLine);}}');
 const installer=path.join(root,release().assets[0].name),compiler=path.join(process.env.SystemRoot,'Microsoft.NET/Framework64/v4.0.30319/csc.exe');
 const compiled=spawnSync(compiler,['/nologo','/target:winexe','/out:'+installer,source],{encoding:'utf8',windowsHide:true});assert.equal(compiled.status,0,compiled.stdout+compiled.stderr);
 await fs.copyFile(installer,path.join(app,'ClawBot实例管理器.exe'));const data=await fs.readFile(installer),marker=path.join(root,'invoked.txt'),job=path.join(root,'full.json');
 const guard=path.join(root,'SetupGuard.exe');const guardSource=fileURLToPath(new URL('../installer/SetupGuard.cs',import.meta.url));const guardBuild=spawnSync(compiler,['/nologo','/reference:System.Management.dll','/out:'+guard,guardSource],{encoding:'utf8',windowsHide:true});assert.equal(guardBuild.status,0,guardBuild.stdout+guardBuild.stderr);
 await fs.writeFile(job,JSON.stringify({download_root:await fs.realpath(root),installer:await fs.realpath(installer),bytes:data.length,sha256:createHash('sha256').update(data).digest('hex'),manager_pid:2147483647,guard,app_root:app,resume_instances:[],jobs_directory:jobs}));
 const script=fileURLToPath(new URL('../src/ApplyUpdate.ps1',import.meta.url));const result=spawnSync('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',script,'-JobFile',job,'-NonInteractive'],{env:{...process.env,CLAWBOT_TEST_MARKER:marker},encoding:'utf8',windowsHide:true,timeout:15000});
 assert.equal(result.status,0,result.stdout+result.stderr);const report=JSON.parse(await fs.readFile(job+'.result.json','utf8'));assert.equal(report.exit_code,0);assert.deepEqual(report.resume_failed,[]);assert.match(await fs.readFile(marker,'utf8'),/\/DIR=/);
});
