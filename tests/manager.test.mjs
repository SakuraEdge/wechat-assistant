import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs/promises';import os from 'node:os';import path from 'node:path';
const temporary=await fs.mkdtemp(path.join(os.tmpdir(),'wechat-manager-test-'));process.env.LOCALAPPDATA=temporary;
const {validName,isBusy,snapshot,config,execute}=await import('../src/controller.mjs');
test('instance names reject traversal and shell text',()=>{for(const name of ['primary','user-2','user-10'])assert.equal(validName(name),true);for(const name of ['../primary','a;pwd','A','a/b','',null])assert.equal(validName(name),false);});
test('busy detection includes active work, queued work, chat and attachments',()=>{for(const value of [{phase:'working'},{queued:1},{chat_busy:true},{attachment_busy:true}])assert.equal(isBusy({running:true,...value}),true);assert.equal(isBusy({running:true,phase:'listening'}),false);assert.equal(isBusy({running:false,phase:'working'}),false);});
test('a fresh profile shows primary as the next instance',async()=>{const value=await snapshot();assert.equal(value.instances.length,0);assert.equal(value.next_name,'primary');});
test('snapshot reads only public status, defaults roles and separates broken configs',async()=>{
 const registry=path.join(temporary,'Codex','wechat-dialog-instances');await fs.mkdir(registry,{recursive:true});
 for(const name of ['user-2','primary']){const data=path.join(temporary,name);await fs.mkdir(data);await fs.writeFile(path.join(registry,name+'.json'),JSON.stringify({name,workspace:path.join(temporary,'workspace',name),data_directory:data}));await fs.writeFile(path.join(data,'status.json'),JSON.stringify({configured:true,logged_in:true,running:true,pid:process.pid,phase:'listening',thread_id:'test-thread'}));}
 await fs.writeFile(path.join(registry,'broken.json'),'invalid');const value=await snapshot();assert.equal(value.instances[0].name,'primary');assert.equal(value.instances[0].policy.role,'owner');assert.equal(value.instances.find(i=>i.name==='user-2').policy.role,'standard');assert.equal(value.instances.find(i=>i.name==='broken').error,'CONFIG_INVALID');assert.equal(value.next_name,'user-3');assert.ok(value.instances[0].running);
});
test('unsupported requests and primary downgrade are rejected before changes',async()=>{
 await assert.rejects(config('../primary'),/INVALID_INSTANCE/);await assert.rejects(execute({action:'something',name:'primary'}),/UNKNOWN_ACTION/);
 await assert.rejects(execute({action:'permissions',name:'primary',role:'standard'}),/PRIMARY_OWNER_REQUIRED/);
});
