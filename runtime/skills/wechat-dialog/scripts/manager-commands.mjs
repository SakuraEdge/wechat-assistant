import fs from 'node:fs/promises';import path from 'node:path';import {randomBytes} from 'node:crypto';
import {policyFor} from './access-policy.mjs';
export async function enqueueDesktopCommand({state,store,dataDir,action,threadId}) {
  if(!policyFor(state).admin)throw Error('MANAGER_PERMISSION_DENIED');
  if(action!=='open-chat'||!/^[a-zA-Z0-9-]{8,80}$/.test(threadId||''))throw Error('INVALID_DESKTOP_COMMAND');
  const id=randomBytes(16).toString('hex');await store.save({id,action,thread_id:threadId,expires:Date.now()+60000},'desktop-commands/'+id);
  return {status:'queued',request_id:id};
}
export async function drainDesktopCommands({rpc,state,store,dataDir}) {
  if((state.instanceId||'primary')!=='primary')return;
  const directory=path.join(dataDir,'desktop-commands');let names;try{names=await fs.readdir(directory);}catch(error){if(error.code==='ENOENT')return;throw error;}
  for(const name of names.filter(name=>/^[a-f0-9]{32}\.dpapi$/.test(name))) {
    const id=name.slice(0,-6);const receiptFile=path.join(directory,id+'.receipt.json');
    try{const handle=await fs.open(receiptFile,'wx');await handle.writeFile(JSON.stringify({status:'in_flight'}));await handle.close();}catch(error){if(error.code==='EEXIST')continue;throw error;}
    let status='submitted',error;
    try{const value=await store.load('desktop-commands/'+id);if(value.action!=='open-chat'||Date.now()>value.expires)throw Error('DESKTOP_COMMAND_EXPIRED');const result=await rpc.request('mcpServer/tool/call',{threadId:state.threadId,server:'codex_app',tool:'navigate_to_codex_page',arguments:{threadId:value.thread_id}},30000);if(result.isError)throw Error('DESKTOP_ACTION_REJECTED');}
    catch(err){status='failed';error=/^[A-Z][A-Z0-9_-]*$/.test(err.message||'')?err.message:'DESKTOP_CONNECTION_UNAVAILABLE';}
    await fs.writeFile(receiptFile,JSON.stringify({status,...(error?{error}:{}),at:new Date().toISOString()}));
  }
}
