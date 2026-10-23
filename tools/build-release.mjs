import fs from 'node:fs/promises';import path from 'node:path';import os from 'node:os';import {fileURLToPath} from 'node:url';import {createHash} from 'node:crypto';import {spawnSync} from 'node:child_process';
import {verifyPayload} from '../installer/verify-payload.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const arg=name=>{const i=process.argv.indexOf(name);return i<0?null:process.argv[i+1];};
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
function run(exe,args,cwd=root){const result=spawnSync(exe,args,{cwd,encoding:'utf8',windowsHide:true,maxBuffer:8*1024*1024,timeout:300000});if(result.status!==0){const error=Error('RELEASE_BUILD_STEP_FAILED');error.step=path.basename(exe);error.diagnostics=(result.stdout||'').slice(-3500)+(result.stderr||'').slice(-1000);throw error;}return result.stdout;}
function allowed(name){return !/(?:^|\/)(?:\.git|node_modules|dist|work|instances|qr|jobs)(?:\/|$)|\.dpapi$|\.log$|\.tmp$|\.receipt\.json$|(?:^|\/)(?:runtime-config|notification-route|state|auth|credentials)\.json$/i.test(name);}
async function copyTree(from,to,relative=''){
 for(const entry of await fs.readdir(from,{withFileTypes:true})){
  const rel=relative?relative+'/'+entry.name:entry.name;if(!allowed(rel))continue;
  if(entry.isSymbolicLink())throw Error('RELEASE_LINK_FORBIDDEN');const target=path.join(to,entry.name),source=path.join(from,entry.name);
  if(entry.isDirectory()){await fs.mkdir(target,{recursive:true});await copyTree(source,target,rel);}else if(entry.isFile())await fs.copyFile(source,target);
 }
}
async function download(url,expected){const response=await fetch(url,{signal:AbortSignal.timeout(180000)});if(!response.ok)throw Error('DEPENDENCY_DOWNLOAD_FAILED');const bytes=Buffer.from(await response.arrayBuffer());if(sha(bytes)!==expected)throw Error('DEPENDENCY_HASH_MISMATCH');return bytes;}
try{
 if(process.platform!=='win32'||process.arch!=='x64')throw Error('WINDOWS_X64_BUILD_REQUIRED');
 const {version}=JSON.parse(await fs.readFile(path.join(root,'package.json'),'utf8')),pins=JSON.parse(await fs.readFile(path.join(root,'installer/dependencies.json'),'utf8'));
 const compiler=arg('--compiler')||process.env.ISCC_PATH;if(!compiler||!path.isAbsolute(compiler))throw Error('ISCC_PATH_REQUIRED');await fs.access(compiler);
 run(process.execPath,[path.join(root,'tools/audit-package.mjs')]);
 const output=path.join(root,'dist','release-v'+version);try{await fs.access(output);throw Error('RELEASE_OUTPUT_ALREADY_EXISTS');}catch(error){if(error.code!=='ENOENT')throw error;}
 const temporary=await fs.mkdtemp(path.join(os.tmpdir(),'clawbot-release-')),payload=path.join(temporary,'ClawBotInstanceManager');await fs.mkdir(payload);
 for(const directory of ['src','assets','runtime','templates','docs','tests','tools','installer']){await fs.mkdir(path.join(payload,directory));await copyTree(path.join(root,directory),path.join(payload,directory),directory);}
 for(const file of ['AGENTS.md','README.md','package.json','runtime-manifest.json','build.ps1','initialize.ps1','打开ClawBot实例管理器.vbs','打开微信助手.vbs'])await fs.copyFile(path.join(root,file),path.join(payload,file));
 const bundled=path.join(payload,'runtime/node/node.exe');let bytes=await fs.readFile(bundled).catch(error=>{if(error.code==='ENOENT')return null;throw error;});
 if(!bytes){bytes=await download(pins.node.url,pins.node.sha256);await fs.mkdir(path.dirname(bundled),{recursive:true});await fs.writeFile(bundled,bytes);}if(sha(bytes)!==pins.node.sha256)throw Error('BUNDLED_NODE_HASH_MISMATCH');
 const npm=process.env.npm_execpath||path.join(path.dirname(process.execPath),'node_modules/npm/bin/npm-cli.js');await fs.access(npm);
 run(process.execPath,[npm,'ci','--omit=dev','--ignore-scripts','--no-audit','--no-fund'],path.join(payload,'runtime/skills/wechat-dialog'));
 run('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(payload,'build.ps1')],payload);
 const csc=path.join(process.env.WINDIR||process.env.SystemRoot,'Microsoft.NET/Framework64/v4.0.30319/csc.exe');
 run(csc,['/nologo','/target:exe','/reference:System.Management.dll','/out:'+path.join(payload,'installer/SetupGuard.exe'),path.join(payload,'installer/SetupGuard.cs')],payload);
 const files=[];async function collect(directory){for(const entry of await fs.readdir(directory,{withFileTypes:true})){const file=path.join(directory,entry.name);if(entry.isSymbolicLink())throw Error('PAYLOAD_LINK_FORBIDDEN');if(entry.isDirectory())await collect(file);else{const relative=path.relative(payload,file).replaceAll('\\','/');if(/\.dpapi$|\.log$|\.receipt\.json$|notification-route\.json$|runtime-config\.json$|(?:^|\/)(?:jobs|qr|instances|work)(?:\/|$)/i.test(relative))throw Error('PRIVATE_FILE_IN_PAYLOAD');const data=await fs.readFile(file);files.push({path:relative,bytes:data.length,sha256:sha(data)});}}}
 await collect(payload);files.sort((a,b)=>a.path.localeCompare(b.path));await fs.writeFile(path.join(payload,'install-manifest.json'),JSON.stringify({schema:1,version,platform:'windows-x64',node_version:pins.node.version,files},null,2)+'\n');
 await verifyPayload(payload);run('powershell.exe',['-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',path.join(payload,'src/Manager.ps1'),'-SelfTest'],payload);
 await fs.mkdir(output,{recursive:true});run(compiler,['/Qp','/DAppVersion='+version,'/DPayloadDir='+payload,'/DOutputDir='+output,'/DNodeSHA256='+pins.node.sha256,path.join(payload,'installer/ClawBot.iss')],payload);
 const zip=path.join(output,'ClawBot-Instance-Manager-'+version+'-windows-x64-portable.zip');
 const compression=spawnSync('powershell.exe',['-NoProfile','-Command','Compress-Archive -LiteralPath $env:CLAWBOT_PAYLOAD -DestinationPath $env:CLAWBOT_ARCHIVE -CompressionLevel Optimal'],{windowsHide:true,env:{...process.env,CLAWBOT_PAYLOAD:payload,CLAWBOT_ARCHIVE:zip},encoding:'utf8',timeout:300000});if(compression.status!==0)throw Error('PORTABLE_COMPRESSION_FAILED');
 const securityReport=path.join(temporary,'defender-scan.json');run('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(root,'tools/scan-release.ps1'),'-Directory',output,'-ReportFile',securityReport]);
 const assets=[];for(const name of await fs.readdir(output)){const data=await fs.readFile(path.join(output,name));assets.push({name,bytes:data.length,sha256:sha(data)});}
 assets.sort((a,b)=>a.name.localeCompare(b.name));const checksum=assets.map(item=>item.sha256+'  '+item.name).join('\n')+'\n';await fs.writeFile(path.join(output,'SHA256SUMS.txt'),checksum);
 const manifest=path.join(output,'install-manifest.json');await fs.copyFile(path.join(payload,'install-manifest.json'),manifest);assets.push({name:'SHA256SUMS.txt',bytes:Buffer.byteLength(checksum),sha256:sha(Buffer.from(checksum))},{name:'install-manifest.json',bytes:(await fs.stat(manifest)).size,sha256:sha(await fs.readFile(manifest))});
 console.log(JSON.stringify({status:'built',version,output,payload,assets,files:files.length,node_version:pins.node.version,security_report:securityReport}));
}catch(error){console.log(JSON.stringify({status:'error',code:/^[A-Z0-9_]+$/.test(error.message)?error.message:'RELEASE_BUILD_FAILED',...(error.step?{step:error.step,diagnostics:error.diagnostics}: {})}));process.exitCode=1;}
