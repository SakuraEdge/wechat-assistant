import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {spawn} from 'node:child_process';
import {randomBytes} from 'node:crypto';
import {setupStatus} from './setup-status.mjs';
import {instancePaths,instanceDataDirectory} from '../runtime/skills/wechat-dialog/scripts/instance-paths.mjs';
import {normalizeUsage} from './account-usage.mjs';
import {checkUpdate,downloadUpdate,verifyInstaller,updateDirectory} from './updates.mjs';
import {launchUpdateHelper} from './update-launch.mjs';
import {installationPlan,isInstalled} from './install-plan.mjs';

export const appRoot=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const {version:appVersion}=JSON.parse(await fs.readFile(path.join(appRoot,'package.json'),'utf8'));
const profile=process.env.LOCALAPPDATA;
const manager=path.join(profile,'Codex','wechat-manager');
const runtime=path.join(appRoot,'runtime','skills');
const scripts=path.join(runtime,'wechat-dialog','scripts');
const bot=path.join(scripts,'wechat-bot.mjs');
const ps=path.join(scripts,'wechat-instance.ps1');
export const validName=name=>typeof name==='string'&&/^[a-z][a-z0-9-]{0,47}$/.test(name);
const alive=pid=>{if(!Number.isInteger(pid)||pid<=0)return false;try{process.kill(pid,0);return true;}catch{return false;}};
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
async function json(file,fallback=null){try{return JSON.parse((await fs.readFile(file,'utf8')).replace(/^\uFEFF/,''));}catch(error){if(error.code==='ENOENT')return fallback;throw Error('CONFIG_INVALID');}}
export async function config(name){if(!validName(name))throw Error('INVALID_INSTANCE');const locations=await instancePaths();const c=await json(path.join(locations.registry,name+'.json'));if(!c||c.name!==name||!path.isAbsolute(c.workspace)||!path.isAbsolute(c.data_directory))throw Error('INSTANCE_NOT_REGISTERED');return {...c,data_directory:instanceDataDirectory(name,c.data_directory,locations)};}
async function modules(){return import(pathToFileURL(path.join(scripts,'access-policy.mjs')));}
async function env(){const {SecureStore}=await import(pathToFileURL(path.join(scripts,'core.mjs')));const {desktopEnvironment}=await import(pathToFileURL(path.join(scripts,'desktop-connection.mjs')));return desktopEnvironment(SecureStore,path.join(scripts,'secure-store.ps1'));}
async function run(exe,args,options={}){
  return new Promise((resolve,reject)=>{
    const child=spawn(exe,args,{windowsHide:true,stdio:['ignore','pipe','pipe'],...options});let stdout='';
    child.stdout.setEncoding('utf8');child.stdout.on('data',chunk=>{stdout+=chunk;if(stdout.length>2_000_000)child.kill();});child.stderr.resume();
    child.on('error',()=>reject(Error('CHILD_START_FAILED')));child.on('exit',code=>{
      let result;for(const line of stdout.split(/\r?\n/)){try{result=JSON.parse(line);}catch{}}
      if(code!==0||result?.status==='error')reject(Error(result?.code||'COMMAND_FAILED'));else resolve(result||{status:'completed'});
    });
  });
}
async function manage(action,name,extra=[]){const environment={...await env(),CODEX_WECHAT_REGISTRY_DIR:(await instancePaths()).registry};return run('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',ps,'-Action',action,'-Name',name,'-NodePath',process.execPath,...extra],{env:environment});}
async function invoke(c,args){return run(process.execPath,[bot,...args],{env:{...await env(),CODEX_WECHAT_INSTANCE:c.name,CODEX_WECHAT_DATA_DIR:c.data_directory}});}
async function current(c){const value=await json(path.join(c.data_directory,'status.json'),{});return {...value,running:!!(value.running&&alive(value.pid))};}
export function isBusy(status){return status.running&&!!(status.phase==='working'||status.queued>0||status.chat_busy||status.attachment_busy);}
async function waitFor(c,predicate,timeout=70000){const end=Date.now()+timeout;do{const value=await current(c);if(predicate(value))return value;await delay(500);}while(Date.now()<end);throw Error('SERVICE_TIMEOUT');}
async function stop(c,{requireIdle=false}={}){
 const value=await current(c);if(!value.running)return {status:'already_stopped'};if(requireIdle&&isBusy(value))throw Error('INSTANCE_BUSY');
 if(requireIdle){
  const id=randomBytes(16).toString('hex');await invoke(c,['stop-idle','--request',id]);const receipt=path.join(c.data_directory,'idle-stop-'+id+'.json');const end=Date.now()+10000;let result;
  while(Date.now()<end){result=await json(receipt);if(result)break;await delay(200);}if(!result)throw Error('SERVICE_TIMEOUT');await fs.unlink(receipt);if(result.status!=='accepted')throw Error('INSTANCE_BUSY');
 }else await invoke(c,['stop']);
 await waitFor(c,s=>!alive(s.pid));return {status:'stopped'};
}
async function prepare(c){const s=await current(c);if(s.configured)return;if(s.running)throw Error('INSTANCE_BUSY');await manage('Prepare',c.name);}
export async function snapshot(){
  const {DEFAULT_PERSONA}=await import(pathToFileURL(path.join(scripts,'persona-profile.mjs')));
  const default_persona={...DEFAULT_PERSONA,references:['gpt-dragon.png','fish-cosplay.png'].map((file,i)=>({path:path.join(appRoot,'templates','workspace','outputs','persona','references',file),label:i?'大肥鱼（cosplay）':'GPT小姐（本体）'}))};
  const {registry}=await instancePaths();
  let names;try{names=(await fs.readdir(registry)).filter(name=>/^[a-z][a-z0-9-]{0,47}\.json$/.test(name));}catch(error){if(error.code==='ENOENT')names=[];else throw error;}
  const labels=await json(path.join(manager,'labels.json'),{});const {loadAccessPolicy}=await modules();
  const instances=await Promise.all(names.map(async file=>{const name=file.slice(0,-5);try{
    const c=await config(name),s=await current(c);const policy=await loadAccessPolicy(c.data_directory,name);
    const {loadModelPolicy}=await import(pathToFileURL(path.join(scripts,'model-policy.mjs')));const selection=await loadModelPolicy(c.data_directory);
    const {loadPersona}=await import(pathToFileURL(path.join(scripts,'persona-profile.mjs')));
    const persona=await loadPersona(c.data_directory,c.workspace,{displayName:labels[name]||name,referenceDir:path.join(appRoot,'templates','workspace','outputs','persona','references')});
    return {name,label:persona.display_name,persona,workspace:c.workspace,data_directory:c.data_directory,configured:!!s.configured,logged_in:!!s.logged_in,running:s.running,phase:s.phase||'unprepared',busy:isBusy(s),reply_ready:!!s.reply_ready,thread_id:s.thread_id||null,policy,last_received_at:s.last_received_at||s.last_chat?.at||null,last_work_finished_at:s.last_work_finished_at||null,queued:s.queued||0,updated_at:s.updated_at||null,project_tools_connected:!!s.project_tools_connected,model:selection.model,reasoning_effort:selection.effort,effective_model:s.model||null,effective_effort:s.reasoning_effort??null,account_fingerprint:s.account_fingerprint||null};
  }catch(error){return {name,label:labels[name]||name,error:error.message,running:false,phase:'needs_attention'};}}));
  instances.sort((a,b)=>a.name==='primary'?-1:b.name==='primary'?1:a.name.localeCompare(b.name,undefined,{numeric:true}));
  const next=instances.length?Math.max(1,...instances.map(item=>Number(item.name.match(/^user-(\d+)$/)?.[1]||1)))+1:1;
  return {status:'ok',version:appVersion,default_persona,notification_recipient:'primary',instances,next_name:instances.some(i=>i.name==='primary')?'user-'+next:'primary',at:new Date().toISOString()};
}
async function installPlan(latestVersion){
 let defaultDirectory;
 if(!await isInstalled(appRoot,appVersion)){const location=await run('powershell.exe',['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(appRoot,'src','install-location.ps1')]);defaultDirectory=location.directory;}
 return installationPlan(appRoot,appVersion,latestVersion,{defaultDirectory});
}
async function updateAction(input,{onProgress}={}){
 const update=await checkUpdate(appVersion);
 if(input.action==='check-update'){try{return {...update,...await installPlan(update.latest_version||appVersion)};}catch(error){return {...update,installed:await isInstalled(appRoot,appVersion),can_install:false,install_reason:error.message};}}
 if(!update.available||update.latest_version!==input.version)throw Error('UPDATE_CHANGED_RECHECK');
 const root=path.join(manager,'updates');
 if(input.action==='download-update')return downloadUpdate(update,root,{onProgress});
 const plan=await installPlan(update.latest_version);
 if(!Number.isSafeInteger(input.manager_pid)||input.manager_pid<=0)throw Error('UPDATE_MANAGER_INVALID');
 if(!/^[0-9]{15,19}$/.test(input.manager_start_ticks||''))throw Error('UPDATE_MANAGER_INVALID');
 const directory=await updateDirectory(root,update.latest_version),file=path.join(directory,update.asset.name);
 await verifyInstaller(file,update.asset,root);
 const instances=[];for(const item of (await snapshot()).instances){const c=await config(item.name),s=await current(c);if(s.running)instances.push({c,s});}
 const processes=await run('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(appRoot,'src','update-processes.ps1'),'-AppRoot',plan.install_directory,'-ProcessIds',instances.map(item=>item.s.pid).join(',')]);
 const owned=instances.filter(item=>processes.processes.some(proc=>proc.pid===item.s.pid&&proc.owned));
 if(owned.some(item=>isBusy(item.s)))throw Error('INSTANCE_BUSY');
 const stopped=[];let child,job;
 try{
  for(const item of owned){stopped.push(item.c.name);await stop(item.c,{requireIdle:true});}
  const script=path.join(directory,'ApplyUpdate.ps1');await fs.copyFile(path.join(appRoot,'src','ApplyUpdate.ps1'),script);
  const guard=path.join(directory,'SetupGuard.exe');await fs.copyFile(path.join(appRoot,'installer','SetupGuard.exe'),guard);
  job=path.join(directory,randomBytes(16).toString('hex')+'.json');const jobs=path.join(manager,'jobs');await fs.mkdir(jobs,{recursive:true});
  await fs.writeFile(job,JSON.stringify({installer:file,download_root:await fs.realpath(root),sha256:update.asset.sha256,bytes:update.asset.size,manager_pid:input.manager_pid,manager_start_ticks:input.manager_start_ticks,guard,app_root:plan.install_directory,manager_root:appRoot,resume_instances:stopped,jobs_directory:jobs}));
  child=launchUpdateHelper(script,job,directory);let failed=false;child.on('error',()=>{failed=true;});
  const deadline=Date.now()+10000;while(!failed&&Date.now()<deadline){if(await fs.access(job+'.ready').then(()=>true,()=>false)){child.unref();return {status:'update_handoff',version:update.latest_version};}if(await fs.access(job+'.error.json').then(()=>true,()=>false))break;await delay(100);}
  throw Error('UPDATE_HANDOFF_FAILED');
 }catch(error){if(job)await fs.writeFile(job+'.cancel','cancel').catch(()=>{});if(child&&!child.killed)child.kill();for(const name of stopped){try{await invoke(await config(name),['start']);}catch{}}throw error;}
}
async function withClient(callback){
 const {SecureStore,RpcClient}=await import(pathToFileURL(path.join(scripts,'core.mjs')));
 let primary;try{primary=await config('primary');}catch(error){if(error.message!=='INSTANCE_NOT_REGISTERED')throw error;}
 const state=await new SecureStore(primary?.data_directory||path.join(profile,'Codex','wechat-dialog'),path.join(scripts,'secure-store.ps1')).load()||{};
 const environment={...await env(),...(state.providerEnv||{})};const executable=state.codex||environment.CODEX_CLI_PATH;if(!executable)throw Error('CODEX_PATH_REQUIRED');
 const rpc=new RpcClient(executable,environment);try{await rpc.initialize();return await callback(rpc);}finally{rpc.close();}
}
export async function catalog({refresh=false}={}){
 const file=path.join(manager,'model-catalog.json');const cached=await json(file);
 if(!refresh&&cached&&Date.now()-Date.parse(cached.retrieved_at)<300000)return cached;
 const {normalizeCatalog}=await import(pathToFileURL(path.join(scripts,'model-policy.mjs')));
 const items=await withClient(async rpc=>{const items=[];let cursor;for(let page=0;page<20;page++){const result=await rpc.request('model/list',{includeHidden:false,limit:100,...(cursor?{cursor}:{})},45000);items.push(...result.data);if(!result.nextCursor){cursor=null;break;}if(result.nextCursor===cursor)throw Error('MODEL_LIST_INCOMPLETE');cursor=result.nextCursor;}if(cursor)throw Error('MODEL_LIST_INCOMPLETE');return items;});
 const models=normalizeCatalog(items);if(!models.length)throw Error('MODEL_LIST_EMPTY');const result={status:'models',source:'codex-model-list',retrieved_at:new Date().toISOString(),models};
 await fs.mkdir(manager,{recursive:true});const tmp=file+'.'+randomBytes(6).toString('hex')+'.tmp';await fs.writeFile(tmp,JSON.stringify(result,null,2));await fs.rename(tmp,file);return result;
}
async function create(input){
  const list=await snapshot();const name=input.name||list.next_name;if(!validName(name))throw Error('INVALID_INSTANCE');
  if(list.instances.some(item=>item.name===name))throw Error('INSTANCE_ALREADY_EXISTS');
  const label=String(input.label||name).trim();if(!label||label.length>60)throw Error('INVALID_LABEL');
  const workspace=path.join(profile,'Codex','wechat-workspaces',name);const template=path.join(appRoot,'templates','workspace');
  if(name==='primary'){
    try{await fs.access(workspace);throw Error('EXISTING_WORKSPACE_NOT_MANAGED');}catch(error){if(error.code!=='ENOENT')throw error;}
    await fs.cp(template,workspace,{recursive:true});await manage('Register',name,['-Workspace',workspace]);
  }else await manage('Create',name,['-Workspace',workspace,'-TemplateWorkspace',template]);
  await fs.mkdir(path.join(workspace,'docs'),{recursive:true});for(const file of ['FEATURES.md','OPERATIONS.md'])await fs.copyFile(path.join(appRoot,'docs',file),path.join(workspace,'docs',file));
  const labels=await json(path.join(manager,'labels.json'),{});labels[name]=label;await fs.mkdir(manager,{recursive:true});await fs.writeFile(path.join(manager,'labels.json'),JSON.stringify(labels,null,2));
  const c=await config(name);await prepare(c);return {status:'created',name,workspace};
}
export async function execute(input,options={}){
  if(!input||typeof input!=='object')throw Error('INVALID_REQUEST');
  if(input.action==='snapshot')return snapshot();
  if(['check-update','download-update','install-update'].includes(input.action))return updateAction(input,options);
  if(input.action==='setup-status')return setupStatus(appRoot,await env(),{verifyClient:input.verify?()=>withClient(rpc=>rpc.request('model/list',{includeHidden:false,limit:1},20000)):null});
  if(input.action==='usage'){
    try{return normalizeUsage(await withClient(rpc=>rpc.request('account/rateLimits/read',{},20000)));}
    catch(error){return {...normalizeUsage(null),reason:error.message==='CODEX_PATH_REQUIRED'?'CLIENT_CONNECTION_REQUIRED':'ACCOUNT_USAGE_UNAVAILABLE'};}
  }
  if(input.action==='models')return catalog({refresh:true});
  if(input.action==='create'){if(!(await setupStatus(appRoot,await env())).ready)throw Error('CLIENT_CONNECTION_REQUIRED');return create(input);}
  const c=await config(input.name);
  if(input.action==='history'){
    const {SecureStore}=await import(pathToFileURL(path.join(scripts,'core.mjs')));
    const {exportConversation}=await import(pathToFileURL(path.join(scripts,'conversation-log.mjs')));
    const state=await new SecureStore(c.data_directory,path.join(scripts,'secure-store.ps1')).load()||{};
    const result=exportConversation(state);
    for(const item of result.messages)for(const secret of [state.credentials?.bot_token,...Object.values(state.providerEnv||{}).filter((_,index)=>/KEY|TOKEN|SECRET|PASSWORD/i.test(Object.keys(state.providerEnv||{})[index]))])if(typeof secret==='string'&&secret.length>5)item.text=item.text.replaceAll(secret,'[已隐藏]');
    return {status:'history',name:c.name,...result,at:new Date().toISOString()};
  }
  if(input.action==='persona-default'){
    const {DEFAULT_PERSONA}=await import(pathToFileURL(path.join(scripts,'persona-profile.mjs')));
    return {status:'persona_default',...DEFAULT_PERSONA,references:['gpt-dragon.png','fish-cosplay.png'].map((file,i)=>({path:path.join(appRoot,'templates','workspace','outputs','persona','references',file),label:i?'大肥鱼（cosplay）':'GPT小姐（本体）'}))};
  }
  if(input.action==='persona'){
    const {preparePersona,savePersona}=await import(pathToFileURL(path.join(scripts,'persona-profile.mjs')));
    const prepared=await preparePersona(input);const s=await current(c);if(isBusy(s))throw Error('INSTANCE_BUSY');
    await stop(c,{requireIdle:true});
    try{await savePersona(c.data_directory,prepared,{defaultReferenceDir:path.join(appRoot,'templates','workspace','outputs','persona','references')});}
    finally{if(s.running){await invoke(c,['start']);await waitFor(c,value=>value.running);}}
    return {status:'persona_saved',name:c.name,restarted:s.running};
  }
  if(input.action==='start'){if(!(await setupStatus(appRoot,await env())).ready)throw Error('CLIENT_CONNECTION_REQUIRED');await prepare(c);const value=await invoke(c,['start']);await waitFor(c,s=>s.running);return value;}
  if(input.action==='stop')return stop(c);
  if(input.action==='restart'){await stop(c,{requireIdle:true});await invoke(c,['start']);await waitFor(c,s=>s.running);return {status:'restarted'};}
  if(input.action==='connect'){
    if(!(await setupStatus(appRoot,await env())).ready)throw Error('CLIENT_CONNECTION_REQUIRED');
    await prepare(c);const s=await current(c);if(s.logged_in&&s.phase!=='needs_attention')return invoke(c,['start']);
    const directory=path.join(manager,'qr');await fs.mkdir(directory,{recursive:true});const qr=path.join(directory,c.name+'.png');
    try{await fs.unlink(qr);}catch(error){if(error.code!=='ENOENT')throw error;}
    try{const result=await invoke(c,['login','--qr',qr]);if(result.status!=='logged_in')return result;return invoke(c,['start']);}
    finally{try{await fs.unlink(qr);}catch{}}
  }
  if(input.action==='permissions'){
    if(!['owner','standard','delegate'].includes(input.role))throw Error('INVALID_ACCESS_ROLE');
    const s=await current(c);if(isBusy(s))throw Error('INSTANCE_BUSY');
    const {saveAccessPolicy}=await modules();const policyInput={role:input.role,capabilities:input.capabilities||{}};
    // Validate before stopping a working listener; policy file changes are local-owner operations.
    if(c.name==='primary'&&(input.role!=='owner'||Object.values(policyInput.capabilities).includes(false)))throw Error('PRIMARY_OWNER_REQUIRED');
    if(c.name!=='primary'&&input.role==='owner')throw Error('PRIMARY_OWNER_REQUIRED');
    for(const [key,value]of Object.entries(policyInput.capabilities))if(!['images','files','projects'].includes(key)||typeof value!=='boolean')throw Error('INVALID_CAPABILITY');
    await stop(c,{requireIdle:true});const policy=await saveAccessPolicy(c.data_directory,c.name,policyInput);
    if(s.running){await invoke(c,['start']);await waitFor(c,value=>value.running);}
    return {status:'permissions_saved',policy,restarted:s.running};
  }
  if(input.action==='model'){
    const s=await current(c);if(isBusy(s))throw Error('INSTANCE_BUSY');
    const available=await catalog({refresh:true});const {validateSelection,saveModelPolicy}=await import(pathToFileURL(path.join(scripts,'model-policy.mjs')));
    const selection=validateSelection(input,available.models);await stop(c,{requireIdle:true});await saveModelPolicy(c.data_directory,selection,available.models);
    if(s.running){await invoke(c,['start']);await waitFor(c,value=>value.running);}
    return {status:'model_saved',selection,restarted:s.running};
  }
  if(input.action==='open-chat'){
    const s=await current(c);if(!s.thread_id)throw Error('CHAT_NOT_READY');const primary=await config('primary');
    const queued=await invoke(primary,['desktop-action','--action','open-chat','--thread',s.thread_id]);
    const receipt=path.join(primary.data_directory,'desktop-commands',queued.request_id+'.receipt.json');const end=Date.now()+40000;
    while(Date.now()<end){const result=await json(receipt);if(result?.status==='submitted')return {status:'opened'};if(result?.status==='failed')throw Error(result.error||'DESKTOP_CONNECTION_UNAVAILABLE');await delay(400);}throw Error('DESKTOP_ACTION_UNCONFIRMED');
  }
  if(input.action==='open-workspace'){spawn('explorer.exe',[c.workspace],{windowsHide:true,detached:true,stdio:'ignore'}).unref();return {status:'opened'};}
  throw Error('UNKNOWN_ACTION');
}
async function main(){
  try{
    if(process.platform!=='win32')throw Error('WINDOWS_REQUIRED');
    let input={action:'snapshot'},progressFile;const index=process.argv.indexOf('--request');
    if(index>=0){const file=path.resolve(process.argv[index+1]||'');const jobRoot=path.join(manager,'jobs')+path.sep;if(!file.startsWith(jobRoot)||!/^[a-f0-9]{32}\.json$/.test(path.basename(file)))throw Error('INVALID_REQUEST_FILE');input=await json(file);progressFile=file+'.progress.json';await fs.unlink(file);}
    const onProgress=progressFile?async value=>{try{await fs.writeFile(progressFile,JSON.stringify(value));}catch{/* A locked progress file must not abort the verified installer download. */}}:undefined;
    console.log(JSON.stringify(await execute(input,{onProgress})));
  }catch(error){console.log(JSON.stringify({status:'error',code:/^[A-Z][A-Z0-9_]+$/.test(error.message)?error.message:'MANAGER_LOCAL_ERROR'}));process.exitCode=1;}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))await main();
