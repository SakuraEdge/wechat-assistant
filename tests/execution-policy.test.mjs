import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs/promises';import path from 'node:path';import os from 'node:os';
import {loadExecutionPolicy,normalizeExecutionPolicy} from '../runtime/skills/wechat-dialog/scripts/execution-policy.mjs';
import {resumeWechatThread,agentTurn,confirmWechatPermissions} from '../runtime/skills/wechat-dialog/scripts/core.mjs';
const directory=await fs.mkdtemp(path.join(os.tmpdir(),'wechat-execution-'));
const full={version:1,instance:'primary',access:'full'};
test('full access needs explicit primary binding, never just an administrator role',async()=>{
 assert.equal((await loadExecutionPolicy(directory,'primary')).access,'workspace');
 for(const instance of ['primary','user-2'])for(const binding of ['primary','user-2'])assert.equal(normalizeExecutionPolicy(instance,{...full,instance:binding}).access,instance==='primary'&&binding==='primary'?'full':'workspace');
 await fs.writeFile(path.join(directory,'execution-policy.json'),JSON.stringify(full));
 assert.equal((await loadExecutionPolicy(directory,'primary')).access,'full');assert.equal((await loadExecutionPolicy(directory,'user-2')).access,'workspace');
 await fs.writeFile(path.join(directory,'execution-policy.json'),'{broken');await assert.rejects(loadExecutionPolicy(directory,'primary'),/EXECUTION_POLICY_INVALID/);
});
test('resume applies and verifies primary full access while preserving the selected model',async()=>{
 const state={instanceId:'primary',executionPolicy:full,threadId:'thread',cwd:directory,modelSelection:{model:'selected-model',effort:'max'}};let sent;
 const rpc={request:async(method,args)=>{assert.equal(method,'thread/resume');sent=args;return {approvalPolicy:args.approvalPolicy,approvalsReviewer:args.approvalsReviewer,sandbox:{type:args.sandbox==='danger-full-access'?'dangerFullAccess':'workspaceWrite'},cwd:directory};}};
 await resumeWechatThread(rpc,state,async()=>{});assert.equal(sent.approvalPolicy,'never');assert.equal(sent.sandbox,'danger-full-access');assert.equal(sent.model,'selected-model');assert.equal(sent.config.model_reasoning_effort,'max');assert.equal(rpc.wechatPermissions.sandbox_mode,'danger-full-access');
 assert.throws(()=>confirmWechatPermissions(rpc,{approvalPolicy:'on-request',approvalsReviewer:'auto_review',sandbox:{type:'workspaceWrite'}},state),/CODEX_PERMISSIONS_NOT_APPLIED/);
 await resumeWechatThread(rpc,{...state,instanceId:'user-2',accessPolicy:{role:'delegate'}},async()=>{});assert.equal(sent.sandbox,'workspace-write');assert.equal(sent.approvalPolicy,'on-request');
});
test('new work threads and every turn retain explicit execution mode and scoped permissions',async()=>{
 for(const instanceId of ['primary','user-2']){
  const state={instanceId,executionPolicy:full,cwd:directory,modelSelection:{model:'selected-model',effort:'high'}};const calls=[];
  const rpc={listeners:new Set(),disconnectListeners:new Set(),request:async(method,args)=>{calls.push({method,args});if(method==='thread/start')return {thread:{id:'thread'},approvalPolicy:args.approvalPolicy,approvalsReviewer:args.approvalsReviewer,sandbox:{type:args.sandbox==='danger-full-access'?'dangerFullAccess':'workspaceWrite'}};if(method==='thread/name/set')return {};if(method==='turn/start'){setTimeout(()=>{for(const listener of rpc.listeners)listener({method:'turn/completed',params:{threadId:'thread',turn:{id:'turn',status:'completed'}}});},0);return {turn:{id:'turn'}};}throw Error('UNEXPECTED_METHOD');}};
  await agentTurn(rpc,state,{id:'task',text:'创建文件'},async()=>{},async()=>{});
  const start=calls.find(x=>x.method==='thread/start').args,turn=calls.find(x=>x.method==='turn/start').args;
  assert.equal(start.sandbox,instanceId==='primary'?'danger-full-access':'workspace-write');assert.equal(turn.approvalPolicy,instanceId==='primary'?'never':'on-request');assert.equal(turn.sandboxPolicy.type,instanceId==='primary'?'dangerFullAccess':'workspaceWrite');
  assert.deepEqual(turn.collaborationMode,{mode:'default',settings:{model:'selected-model',reasoning_effort:'high',developer_instructions:null}});
 }
});
