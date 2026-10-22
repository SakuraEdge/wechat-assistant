import fs from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { freezeOutgoingFile, outputsArtifact, extractFileMarkers } from './file-transfer.mjs';
import {policyFor} from './access-policy.mjs';
const digest = value => createHash('sha256').update(value).digest('hex');
const errorCode = error => /^[A-Z][A-Z0-9_-]*$/.test(error.message||'') ? error.message : 'FILE_LOCAL_OPERATION_FAILED';

export async function queueProjectFile({state,store,dataDir,source,event,caption=''}) {
  if(!state.credentials?.ilink_user_id||!state.context)throw Error('MISSING_REPLY_CONTEXT');
  if(!/^[a-zA-Z0-9-]{8,80}$/.test(source?.project_id||'')||!/^[a-zA-Z0-9-]{8,80}$/.test(source?.thread_id||'')||typeof source.path!=='string'||!path.isAbsolute(source.path)||typeof event!=='string'||!event||event.length>256||typeof caption!=='string'||caption.length>2000)throw Error('INVALID_PROJECT_FILE_EVENT');
  const id=digest('project-file:'+event);const directory=path.join(dataDir,'outbox');await fs.mkdir(directory,{recursive:true});
  try{const reservation=await fs.open(path.join(directory,id+'.reserved'),'wx');await reservation.close();}catch(error){if(error.code!=='EEXIST')throw error;return {status:'duplicate',event_hash:id,delivery:'unconfirmed'};}
  await store.save({id,title:'',content:caption,project_ref:source,context:state.context,kind:'file'},'outbox/'+id);
  return {status:'queued',event_hash:id,delivery:'unconfirmed'};
}

export async function queueOutgoingFile({ state, store, dataDir, filename, event, caption = '', displayName, context }) {
  if(!policyFor(state).capabilities.files)throw Error('FILE_ACCESS_DENIED');
  if (!state.credentials?.ilink_user_id || !(context || state.context)) throw Error('MISSING_REPLY_CONTEXT');
  if (typeof event !== 'string' || !event || event.length > 256 || typeof caption !== 'string' || caption.length > 2000) throw Error('INVALID_FILE_EVENT');
  const id = digest('file:' + event); const directory = path.join(dataDir, 'outbox');
  await fs.mkdir(directory, { recursive: true });
  try { const handle = await fs.open(path.join(directory, id + '.reserved'), 'wx'); await handle.close(); }
  catch (error) { if (error.code !== 'EEXIST') throw error; return { status: 'duplicate', event_hash: id, delivery: 'unconfirmed' }; }
  try {
    const file = await freezeOutgoingFile(filename, path.join(state.cwd, 'work', 'wechat-outgoing-files'), id, displayName);
    await store.save({ id, title: '', content: caption, files: [file], context: context || state.context, kind: 'file' }, 'outbox/' + id);
    return { status: 'queued', event_hash: id, file_name: file.name, file_size: file.size, delivery: 'unconfirmed' };
  } catch (error) {
    await fs.writeFile(path.join(directory, id + '.receipt.json'), JSON.stringify({ status: 'failed', stage: 'local_prepare', error: errorCode(error), time: new Date().toISOString() }));
    throw error;
  }
}
export async function queueResultFiles({ state, store, dataDir, entry, text }) {
  let parsed;
  try { parsed = extractFileMarkers(text); }
  catch (error) { return { text: text.replace(/\[\[WECHAT_FILE:[^\]\r\n]*\]\]/g,''), files: [], errors: [errorCode(error)] }; }
  const files = [], errors = [];
  for (let i = 0; i < parsed.files.length; i++) {
    if (entry.cancelRequested) { errors.push('FILE_SEND_CANCELLED'); break; }
    try {
      const filename = await outputsArtifact(state.cwd, parsed.files[i]);
      files.push(await queueOutgoingFile({ state, store, dataDir, filename, context: entry.context,
        event: 'task:' + entry.id + ':file:' + i + ':v1' }));
    } catch (error) { errors.push(errorCode(error)); }
  }
  return { text: parsed.text, files, errors };
}
