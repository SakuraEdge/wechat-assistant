import fs from 'node:fs/promises';
import path from 'node:path';

// Trusted per-instance Windows data only. Never infer access from a message,
// an attachment, the workspace, or the business administrator role.
export const EXECUTION_POLICY_VERSION='wechat-execution-v1';
export function normalizeExecutionPolicy(instance,value={}) {
  return {version:1,instance,access:instance==='primary'&&value.version===1&&value.instance==='primary'&&value.access==='full'?'full':'workspace'};
}
export async function loadExecutionPolicy(directory,instance) {
  const filename=path.join(directory,'execution-policy.json');
  try {
    const stat=await fs.lstat(filename);
    if(!stat.isFile()||stat.isSymbolicLink()||stat.size>4096)throw Error('EXECUTION_POLICY_INVALID');
    const value=JSON.parse(await fs.readFile(filename,'utf8'));
    if(!value||Array.isArray(value)||typeof value!=='object'||Object.keys(value).some(key=>!['version','instance','access'].includes(key)))throw Error('EXECUTION_POLICY_INVALID');
    return normalizeExecutionPolicy(instance,value);
  } catch(error) {
    if(error.code==='ENOENT')return normalizeExecutionPolicy(instance);
    throw Error('EXECUTION_POLICY_INVALID');
  }
}
export const fullExecution=state=>state.instanceId==='primary'&&normalizeExecutionPolicy(state.instanceId,state.executionPolicy).access==='full';
