import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {instancePaths,instanceDataDirectory} from '../runtime/skills/wechat-dialog/scripts/instance-paths.mjs';
import {desktopEnvironment} from '../runtime/skills/wechat-dialog/scripts/desktop-connection.mjs';

const temporary=await fs.mkdtemp(path.join(os.tmpdir(),'clawbot-profiles-'));
test.after(()=>fs.rm(temporary,{recursive:true,force:true}));
async function fixture(name){const local=path.join(temporary,name);await fs.mkdir(local);return {LOCALAPPDATA:local};}
async function register(env,packaged=false,name='primary'){
  const root=packaged?path.join(env.LOCALAPPDATA,'Packages','OpenAI.Codex_test','LocalCache','Local','Codex'):path.join(env.LOCALAPPDATA,'Codex');
  const registry=path.join(root,'wechat-dialog-instances');await fs.mkdir(registry,{recursive:true});
  const data=path.join(env.LOCALAPPDATA,'Codex',...(name==='primary'?['wechat-dialog']:['wechat-dialog-instances',name]));
  await fs.writeFile(path.join(registry,name+'.json'),JSON.stringify({name,workspace:path.join(temporary,'workspace',name),data_directory:data}));
  return {registry,data_root:root};
}
test('fresh profiles keep the ordinary registration location',async()=>{
  const env=await fixture('fresh');assert.equal((await instancePaths(env)).registry,path.join(env.LOCALAPPDATA,'Codex','wechat-dialog-instances'));
});
test('desktop startup discovers existing packaged registrations without moving files',async()=>{
  const env=await fixture('packaged');const expected=await register(env,true);await register(env,true,'user-2');
  const before=await fs.readFile(path.join(expected.registry,'primary.json'));const locations=await instancePaths(env);
  assert.deepEqual(locations,expected);assert.equal((await fs.readdir(locations.registry)).length,2);
  for(const name of ['primary','user-2']){
    const original=path.join(env.LOCALAPPDATA,'Codex',...(name==='primary'?['wechat-dialog']:['wechat-dialog-instances',name]));
    const resolved=instanceDataDirectory(name,original,locations,env);
    assert.equal(resolved,path.join(expected.data_root,...(name==='primary'?['wechat-dialog']:['wechat-dialog-instances',name])));
    assert.equal(instanceDataDirectory(name,resolved,locations,env),resolved);
  }
  const custom=path.join(temporary,'custom-data');assert.equal(instanceDataDirectory('primary',custom,locations,env),custom);
  assert.deepEqual(await fs.readFile(path.join(expected.registry,'primary.json')),before);
});
test('empty packaged directories do not hide ordinary instances',async()=>{
  const env=await fixture('ordinary');const expected=await register(env);await fs.mkdir(path.join(env.LOCALAPPDATA,'Packages','OpenAI.Codex_empty','LocalCache','Local','Codex','wechat-dialog-instances'),{recursive:true});
  assert.deepEqual(await instancePaths(env),expected);
});
test('distinct populated registries require explicit selection, never merge identities',async()=>{
  const env=await fixture('ambiguous');await register(env);const packaged=await register(env,true);
  await assert.rejects(instancePaths(env),/INSTANCE_REGISTRY_AMBIGUOUS/);
  assert.deepEqual(await instancePaths({...env,CODEX_WECHAT_REGISTRY_DIR:packaged.registry}),packaged);
  await assert.rejects(instancePaths({...env,CODEX_WECHAT_REGISTRY_DIR:'relative'}),/INVALID_INSTANCE_REGISTRY/);
});
test('logical and physical aliases of one registry are deduplicated',async()=>{
  const env=await fixture('alias');const expected=await register(env,true);await fs.mkdir(path.join(env.LOCALAPPDATA,'Codex'));
  await fs.symlink(expected.registry,path.join(env.LOCALAPPDATA,'Codex','wechat-dialog-instances'),process.platform==='win32'?'junction':'dir');
  assert.deepEqual(await instancePaths(env),expected);
});
test('desktop connection reads the original packaged store without copying credentials',async()=>{
  const env=await fixture('connection');const locations=await register(env,true);const directory=path.join(locations.data_root,'wechat-manager');
  await fs.mkdir(directory);await fs.writeFile(path.join(directory,'desktop-connection.dpapi'),'opaque-test-bytes');
  const seen=[];class Store{constructor(root){seen.push(root);}async load(name){assert.equal(name,'desktop-connection');return {CODEX_CLI_PATH:path.join(temporary,'test-cli.exe'),CODEX_APP_TOOLS_PIPE_PATH:'test-pipe',UNLISTED_SECRET:'not-exported'};}}
  const resolved=await desktopEnvironment(Store,'unused',env);
  assert.deepEqual(seen,[directory]);assert.equal(resolved.CODEX_APP_TOOLS_PIPE_PATH,'test-pipe');assert.equal(resolved.UNLISTED_SECRET,undefined);
  await assert.rejects(fs.access(path.join(env.LOCALAPPDATA,'Codex','wechat-manager','desktop-connection.dpapi')));
});
test('PowerShell management and controller resolve the same registered data paths',{skip:process.platform!=='win32'},async()=>{
  const env=await fixture('powershell');const expected=await register(env,true);await register(env,true,'user-2');
  const script=fileURLToPath(new URL('../runtime/skills/wechat-dialog/scripts/wechat-instance.ps1',import.meta.url));
  for(const name of ['primary','user-2']){
    const result=spawnSync('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',script,'-Action','Info','-Name',name,'-NodePath',process.execPath],{env:{...process.env,...env,CODEX_WECHAT_REGISTRY_DIR:''},encoding:'utf8',windowsHide:true});
    assert.equal(result.status,0,result.stdout);const value=JSON.parse(result.stdout.trim());
    assert.equal(value.data_directory,path.join(expected.data_root,...(name==='primary'?['wechat-dialog']:['wechat-dialog-instances',name])));
    assert.equal(value.workspace,path.join(temporary,'workspace',name));
  }
});
