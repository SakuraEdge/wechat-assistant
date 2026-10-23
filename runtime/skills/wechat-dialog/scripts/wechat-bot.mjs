import fs from 'node:fs/promises';
import path from 'node:path';
import { ACK_STICKER_VERSION } from './ack-stickers.mjs';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { createInterface } from 'node:readline/promises';
import { ROUTING_VERSION, entryIntent, isPendingEntry } from './message-routing.mjs';
import { fastChat } from './fast-chat.mjs';
import { WorkProgress } from './work-progress.mjs';
import { NativeChat } from './native-chat.mjs';
import { FILE_TRANSFER_VERSION, MAX_FILE_BYTES, receiveFileBatch,validateLocalFile } from './file-transfer.mjs';
import { queueOutgoingFile, queueResultFiles,queueProjectFile } from './file-delivery.mjs';
import {PROJECT_BRIDGE_VERSION,loadProjectToolConfig,prepareProjectResults,callProjectTool} from './project-bridge.mjs';
import {QUESTION_BROKER_VERSION,QuestionBroker} from './question-broker.mjs';
import {ACCESS_POLICY_VERSION,loadAccessPolicy,policyFor,deniedRequest} from './access-policy.mjs';
import {loadExecutionPolicy} from './execution-policy.mjs';
import {desktopEnvironment} from './desktop-connection.mjs';
import {instancePaths,instanceDataDirectory} from './instance-paths.mjs';
import {enqueueDesktopCommand,drainDesktopCommands} from './manager-commands.mjs';
import {loadModelPolicy,modelFor,MODEL_POLICY_VERSION} from './model-policy.mjs';
import {runtimePersona,PERSONA_VERSION} from './persona-profile.mjs';
import {observeOutgoing} from './conversation-log.mjs';
import { downloadIncomingImage, validateLocalImage, uploadWechatImage } from './media.mjs';
import { WechatApi, SecureStore, RpcClient, agentTurn, ingest, sleep, splitText, digest, checkedBase, WECHAT_PERMISSIONS, WECHAT_MODEL, WECHAT_THREAD_MODEL, confirmWechatPermissions, resumeWechatThread, acknowledgeEntry, isControlMessage } from './core.mjs';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const locations=await instancePaths();
process.env.CODEX_WECHAT_REGISTRY_DIR=locations.registry;
const dataDir = instanceDataDirectory(process.env.CODEX_WECHAT_INSTANCE||'primary',process.env.CODEX_WECHAT_DATA_DIR || path.join(process.env.LOCALAPPDATA, 'Codex', 'wechat-dialog'),locations);
const store = new SecureStore(dataDir, path.join(scriptDir, 'secure-store.ps1'));
const metaFile = path.join(dataDir, 'status.json');
const lockFile = path.join(dataDir, 'worker.lock');
const stopFile = path.join(dataDir, 'stop.request');
const idleStopFile=path.join(dataDir,'idle-stop.request');
const args = process.argv.slice(2);
const command = args[0] || 'status';
const option = name => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; };
const output = value => console.log(JSON.stringify(value));
const safeError = error => /^[A-Z][A-Z0-9_-]*$/.test(error?.message || '') ? error.message : 'LOCAL_OPERATION_FAILED';
const alive = pid => { try { process.kill(pid, 0); return true; } catch { return false; } };
const publicMeta = async value => { await fs.mkdir(dataDir, { recursive: true }); const tmp=metaFile+'.'+process.pid+'.tmp';await fs.writeFile(tmp, JSON.stringify({...value,updated_at:new Date().toISOString()}));await fs.rename(tmp,metaFile); };
const loadMeta = async () => { try { return JSON.parse(await fs.readFile(metaFile, 'utf8')); } catch { return {}; } };
const persistedEnv = state => ({ ...process.env, ...(state.providerEnv || {}) });

async function prepare() {
  const meta = await loadMeta();
  if (meta.pid && alive(meta.pid)) throw new Error('STOP_WORKER_BEFORE_PREPARE');
  const existing = await store.load() || {};
  existing.instanceId = process.env.CODEX_WECHAT_INSTANCE || existing.instanceId || 'primary';
  existing.cwd = option('--cwd') || existing.cwd || process.cwd();
  existing.codex = option('--codex') || existing.codex || process.env.CODEX_CLI_PATH;
  if (!existing.codex) throw new Error('CODEX_PATH_REQUIRED');
  existing.providerEnv ||= {};
  if(existing.instanceId!=='primary'&&!existing.providerEnv.OPENAI_API_KEY&&!process.env.OPENAI_API_KEY){
    const primary=new SecureStore(path.join(locations.data_root,'wechat-dialog'),path.join(scriptDir,'secure-store.ps1'));
    const shared=await primary.load();
    for(const key of ['OPENAI_API_KEY','OPENAI_BASE_URL'])if(shared?.providerEnv?.[key])existing.providerEnv[key]=shared.providerEnv[key];
  }
  for (const key of ['OPENAI_API_KEY', 'OPENAI_BASE_URL']) {
    if (process.env[key]) existing.providerEnv[key] = process.env[key];
  }
  existing.pending ||= []; existing.seen ||= {};
  existing.modelSelection=await loadModelPolicy(dataDir);
  await store.save(existing);
  await publicMeta({ configured: true, logged_in: !!existing.credentials, running: false, phase: 'prepared', instance: existing.instanceId, model: WECHAT_MODEL.model, reasoning_effort: WECHAT_MODEL.effort, workspace: existing.cwd, data_directory: dataDir });
  output({ status: 'prepared', model: WECHAT_MODEL.model, reasoning_effort: WECHAT_MODEL.effort, instance: existing.instanceId, provider_configuration: 'existing_environment', cwd: existing.cwd });
}

async function login() {
  const state = await store.load();
  if (!state?.codex) throw new Error('RUN_PREPARE_FIRST');
  const meta = await loadMeta();
  if (meta.pid && alive(meta.pid)) throw new Error('STOP_WORKER_BEFORE_LOGIN');
  const qrPath = option('--qr') || path.join(process.cwd(), 'outputs', 'wechat-clawbot-login.png');
  const api = new WechatApi();
  const qr = await api.request('/ilink/bot/get_bot_qrcode?bot_type=3', {
    auth: false, body: { local_token_list: state.credentials?.bot_token ? [state.credentials.bot_token] : [] }
  });
  if (!qr.qrcode || !qr.qrcode_img_content) throw new Error('INVALID_QR_RESPONSE');
  const qrcode = await import('qrcode');
  await fs.mkdir(path.dirname(qrPath), { recursive: true });
  await qrcode.default.toFile(qrPath, qr.qrcode_img_content, { width: 420, margin: 3 });
  output({ status: 'scan_required', qr_path: qrPath, expires_in_seconds: 300 });
  if (args.includes('--show-qr')) {
    const viewer = spawn('powershell.exe', ['-NoProfile', '-Command', 'Start-Process -FilePath $env:CODEX_WECHAT_QR_FILE'],
      { windowsHide: true, stdio: 'ignore', env: { ...process.env, CODEX_WECHAT_QR_FILE: qrPath } });
    viewer.on('error', () => {}); viewer.unref();
  }
  let base = api.base;
  const deadline = Date.now() + 300000;
  let verifyCode;
  while (Date.now() < deadline) {
    let response;
    try {
      response = await api.request('/ilink/bot/get_qrcode_status?qrcode=' + encodeURIComponent(qr.qrcode) +
        (verifyCode ? '&verify_code=' + encodeURIComponent(verifyCode) : ''), { auth: false, base });
      verifyCode = undefined;
    } catch (error) {
      if (safeError(error).startsWith('WECHAT_HTTP_4')) throw error;
      await sleep(1500); continue;
    }
    if (response.status === 'confirmed') {
      if (!response.bot_token || !response.ilink_user_id || !response.ilink_bot_id) throw new Error('INCOMPLETE_LOGIN_IDENTITY');
      const credentials = {
        bot_token: response.bot_token, ilink_user_id: response.ilink_user_id,
        ilink_bot_id: response.ilink_bot_id, baseurl: checkedBase(response.baseurl || base)
      };
      if (state.credentials && state.credentials.ilink_user_id !== credentials.ilink_user_id) {
        throw new Error('DIFFERENT_OWNER_REQUIRES_NEW_DATA_DIRECTORY');
      }
      state.credentials = credentials; state.cursor = '';
      await store.save(state);
      await publicMeta({ configured: true, logged_in: true, running: false, phase: 'ready' });
      output({ status: 'logged_in', credentials_saved: 'windows_dpapi', next: 'start' });
      return;
    }
    if (response.status === 'need_verifycode') {
      if (!process.stdin.isTTY) {
        output({ status: 'local_verification_required', detail: 'Run login in a local terminal and enter the verification code there.' });
        return;
      }
      const terminal = createInterface({ input: process.stdin, output: process.stdout });
      verifyCode = (await terminal.question('WeChat verification code (enter locally): ')).trim();
      terminal.close();
    } else if (response.status === 'scaned_but_redirect' && response.redirect_host) {
      base = checkedBase(response.redirect_host.startsWith('https://') ? response.redirect_host : 'https://' + response.redirect_host);
    } else if (['expired', 'verify_code_blocked', 'binded_redirect'].includes(response.status)) {
      throw new Error('QR_' + response.status.toUpperCase());
    }
    await sleep(1000);
  }
  throw new Error('QR_EXPIRED');
}

async function smoke() {
  const state = await store.load();
  if (!state?.codex) throw new Error('RUN_PREPARE_FIRST');
  state.accessPolicy=await loadAccessPolicy(dataDir,state.instanceId||'primary');
  state.executionPolicy=await loadExecutionPolicy(dataDir,state.instanceId||'primary');
  state.modelSelection=await loadModelPolicy(dataDir);
  const meta = await loadMeta();
  if (meta.pid && alive(meta.pid)) throw new Error('WORKER_ALREADY_RUNNING');
  const rpc = new RpcClient(state.codex, persistedEnv(state),undefined,{appTools:true});
  rpc.projectConfig=await loadProjectToolConfig(process.env,policyFor(state));
  try {
    await rpc.initialize();
    rpc.availableMcpServers=Object.keys((await rpc.request('config/read',{includeLayers:false})).config.mcp_servers||{});
    await resumeWechatThread(rpc, state, () => store.save(state));
    const entry = { id: 'connection-test-' + randomBytes(8).toString('hex'), text: '这是连接测试。不要调用工具，只回复“微信对话服务连接测试通过”。' };
    const result = await agentTurn(rpc, state, entry, () => store.save(state), async () => ({ decision: 'decline' }));
    output({ status: result.status, model: WECHAT_MODEL.model, reasoning_effort: WECHAT_MODEL.effort, reply: result.text, ...(rpc.wechatPermissions || {}) });
  } finally { rpc.close(); }
}

async function start() {
  const state = await store.load();
  if (!state?.credentials) throw new Error('WECHAT_LOGIN_REQUIRED');
  const meta = await loadMeta();
  if (meta.pid && alive(meta.pid)) { output({ status: 'already_running', pid: meta.pid }); return; }
  try { await fs.unlink(stopFile); } catch { }
  const log = await fs.open(path.join(dataDir, 'worker.log'), 'a');
  const child = spawn(process.execPath, [fileURLToPath(import.meta.url), 'run'], {
    env: process.env, detached: true, windowsHide: true, stdio: ['ignore', log.fd, log.fd]
  });
  child.unref(); await log.close();
  await sleep(1800);
  const current = await loadMeta();
  output({ status: current.running && alive(current.pid) ? 'running' : 'starting', pid: child.pid });
}

async function enqueueNotification() {
  const meta = await loadMeta();
  if (!(meta.running && alive(meta.pid) && meta.reply_ready)) {
    output({ status: 'bridge_unavailable', detail: 'Log in, start the listener, and send one WeChat message first.' });
    process.exitCode = 1; return;
  }
  const filename = option('--message');
  if (!filename) throw new Error('MESSAGE_FILE_REQUIRED');
  const value = JSON.parse(await fs.readFile(filename, 'utf8'));
  if (!['event_id', 'title', 'content'].every(key => typeof value[key] === 'string' && value[key].trim()) ||
      Object.keys(value).some(key => !['event_id', 'title', 'content'].includes(key)) ||
      value.event_id.length > 256 || value.title.length > 100 || value.content.length > 10000) throw new Error('INVALID_MESSAGE_FILE');
  const id = digest(value.event_id); const directory = path.join(dataDir, 'outbox');
  await fs.mkdir(directory, { recursive: true });
  try { const reservation = await fs.open(path.join(directory, id + '.reserved'), 'wx'); await reservation.close(); }
  catch (error) {
    if (error.code !== 'EEXIST') throw error;
    output({ status: 'duplicate', channel: 'clawbot', detail: 'This event was already queued; not resent.' }); return;
  }
  await store.save({ id, title: value.title, content: value.content }, 'outbox/' + id);
  output({ status: 'queued', channel: 'clawbot', event_hash: id, delivery: 'unconfirmed' });
}

async function enqueueImage() {
  const meta = await loadMeta();
  if (!(meta.running && alive(meta.pid) && meta.reply_ready)) throw new Error('BRIDGE_UNAVAILABLE');
  const filename = option('--image');
  const event = option('--event');
  if (!filename || !event || event.length > 256) throw new Error('IMAGE_AND_EVENT_REQUIRED');
  const image = await validateLocalImage(filename);
  const caption = option('--caption') || '';
  if (caption.length > 2000) throw new Error('CAPTION_TOO_LONG');
  const id = digest('image:' + event);
  const directory = path.join(dataDir, 'outbox');
  await fs.mkdir(directory, { recursive: true });
  try { const reservation = await fs.open(path.join(directory, id + '.reserved'), 'wx'); await reservation.close(); }
  catch (error) { if (error.code !== 'EEXIST') throw error; output({ status: 'duplicate', event_hash: id }); return; }
  await store.save({ id, title: '', content: caption, images: [image.path] }, 'outbox/' + id);
  output({ status: 'queued', channel: 'clawbot', event_hash: id, image_count: 1, delivery: 'unconfirmed' });
}

async function enqueueFile() {
  const meta = await loadMeta();
  if (!(meta.running && alive(meta.pid) && meta.reply_ready)) throw Error('BRIDGE_UNAVAILABLE');
  const state = await store.load();
  const filename = option('--file'); const event = option('--event');
  if (!filename || !event) throw Error('FILE_AND_EVENT_REQUIRED');
  output(await queueOutgoingFile({ state, store, dataDir, filename, event, caption: option('--caption') || '' }));
}

async function enqueueProjectFile() {
  const meta=await loadMeta();if(!(meta.running&&alive(meta.pid)&&meta.reply_ready))throw Error('BRIDGE_UNAVAILABLE');
  const state=await store.load();
  output(await queueProjectFile({state,store,dataDir,event:option('--event'),caption:option('--caption')||'',source:{project_id:option('--project'),thread_id:option('--thread'),path:option('--file')}}));
}
async function desktopAction() {
  const meta=await loadMeta();if(!(meta.running&&alive(meta.pid)))throw Error('BRIDGE_UNAVAILABLE');
  const state=await store.load();state.accessPolicy=await loadAccessPolicy(dataDir,state.instanceId||'primary');
  output(await enqueueDesktopCommand({state,store,dataDir,action:option('--action'),threadId:option('--thread')}));
}

async function imageTest() {
  const state = await store.load();
  if (!state?.credentials || !state.context) throw new Error('MISSING_REPLY_CONTEXT');
  const filename = option('--image'); const event = option('--event');
  if (!filename || !event) throw new Error('IMAGE_AND_EVENT_REQUIRED');
  const id = digest('image-test:' + event);
  const directory = path.join(state.cwd, 'outputs');
  const reportFile = path.join(directory, 'wechat-image-test-' + id.slice(0, 12) + '.json');
  await fs.mkdir(directory, { recursive: true });
  let reservation;
  try { reservation = await fs.open(reportFile, 'wx'); }
  catch (error) { if (error.code !== 'EEXIST') throw error; output({ status: 'duplicate', report: reportFile }); return; }
  const report = { status: 'testing', cdn_roundtrip_verified: false, send_status: 'not_attempted', incoming_phone_image: 'not_verified' };
  await reservation.writeFile(JSON.stringify(report)); await reservation.close();
  const saveReport = () => fs.writeFile(reportFile, JSON.stringify(report, null, 2));
  let rpc;
  try {
    const api = new WechatApi(state.credentials);
    const image = await validateLocalImage(filename);
    const item = await uploadWechatImage(api, image.path, state.credentials.ilink_user_id);
    report.send_status = 'attempting'; await saveReport();
    await api.sendItems(state.credentials.ilink_user_id, state.context, [item], 'cw-image-test-' + id.slice(0, 32));
    report.send_status = 'accepted'; await saveReport();
    let downloaded = image.path;
    try {
      downloaded = await downloadIncomingImage(api, item.image_item, path.join(state.cwd, 'work', 'wechat-image-test'), id);
      report.cdn_roundtrip_verified = digest(await fs.readFile(downloaded)) === digest(image.bytes);
    } catch (error) { report.download_error = safeError(error); report.download_hints = error.diagnosticHints || []; }
    rpc = new RpcClient(state.codex, persistedEnv(state));
    await rpc.initialize();
    const thread = await rpc.request('thread/start', { cwd: state.cwd, ...WECHAT_THREAD_MODEL, ephemeral: true, ...WECHAT_PERMISSIONS });
    confirmWechatPermissions(rpc, thread);
    const result = await agentTurn(rpc, { cwd: state.cwd, threadId: thread.thread.id }, {
      id: 'vision-' + id, imagePaths: [downloaded], text: '这是图片通道测试。不要调用工具，请简短说出图中的大写英文单词和主背景颜色。'
    }, async () => {}, async () => ({ decision: 'decline' }));
    report.vision_status = result.status;
    report.vision_reply = result.text;
    report.vision_verified = result.status === 'completed' && /GPT/i.test(result.text) && /蓝/.test(result.text);
    report.status = 'completed';
  } catch (error) {
    report.status = 'failed'; report.error = safeError(error); report.error_hints = error.diagnosticHints || [];
    if (report.send_status === 'attempting') report.send_status = 'unknown';
  } finally { rpc?.close(); await saveReport(); }
  output({ ...report, report: reportFile });
}

async function run() {
  const state = await store.load();
  if (!state?.credentials) throw new Error('WECHAT_LOGIN_REQUIRED');
  state.accessPolicy=await loadAccessPolicy(dataDir,state.instanceId||'primary');
  state.executionPolicy=await loadExecutionPolicy(dataDir,state.instanceId||'primary');
  state.modelSelection=await loadModelPolicy(dataDir);
  state.persona=await runtimePersona(dataDir,state.cwd);
  await fs.mkdir(dataDir, { recursive: true });
  try { const lock = JSON.parse(await fs.readFile(lockFile, 'utf8')); if (alive(lock.pid)) throw new Error('WORKER_ALREADY_RUNNING'); await fs.unlink(lockFile); }
  catch (error) { if (safeError(error) === 'WORKER_ALREADY_RUNNING') throw error; }
  const handle = await fs.open(lockFile, 'wx');
  await handle.writeFile(JSON.stringify({ pid: process.pid })); await handle.close();
  const api = observeOutgoing(new WechatApi(state.credentials),state);
  const rpc = new RpcClient(state.codex, persistedEnv(state),undefined,{appTools:true});
  rpc.projectConfig=await loadProjectToolConfig(process.env,policyFor(state));
  let running = true; let busy = false; let chatBusy = false; let attachmentBusy = false; let unhealthy = false; let outboxBusy = false;
  const questionDir=path.join(locations.data_root,'wechat-questions');
  const questionBroker=new QuestionBroker(questionDir,new SecureStore(questionDir,path.join(scriptDir,'secure-store.ps1')));
  let questionSyncBusy=false,lastQuestionSync=0;
  let desktopCommandsBusy=false;
  let chatController; let progress; let nativeChat;
  const approvals = new Map();
  const persist = () => store.save(state);
  const meta = phase => publicMeta({ configured: true, logged_in: true, running, pid: process.pid, phase, reply_ready: !!state.context, queued: state.pending.filter(e => e.status === 'queued').length, instance: state.instanceId || 'primary', workspace: state.cwd, data_directory: dataDir, model: modelFor(state).model, reasoning_effort: modelFor(state).effort, model_policy_version: MODEL_POLICY_VERSION, persona_version:PERSONA_VERSION, assistant_name:state.persona.assistant_name, ...(rpc.wechatPermissions || { permissions_verified: false }), last_ack_at: state.lastAckAt || null, ack_sticker_version: ACK_STICKER_VERSION, last_ack_sticker_at: state.lastAckImageAt || null, thread_recovered: !!rpc.threadRecovered, routing_version: ROUTING_VERSION, chat_busy: chatBusy, last_chat: state.lastChat || null, last_work_finished_at: state.lastWorkResult?.at || null, file_transfer_version: FILE_TRANSFER_VERSION, max_file_bytes: MAX_FILE_BYTES, attachment_busy: attachmentBusy, last_file_received_at: state.lastFileReceivedAt || null, last_file_sent_at: state.lastFileSentAt || null, received_file_count: state.receivedFileCount || 0, sent_file_count: state.sentFileCount || 0, thread_id: state.threadId, account_fingerprint: digest(state.credentials.ilink_user_id).slice(0,8), access_policy_version: ACCESS_POLICY_VERSION, access_policy: policyFor(state), last_received_at: state.lastReceivedAt || null, question_broker_version: QUESTION_BROKER_VERSION, project_bridge_version: PROJECT_BRIDGE_VERSION, project_tools_connected: !!rpc.projectToolsConnected });
  const log = status => output({ time: new Date().toISOString(), status });
  const redact = value => {
    let text = String(value || '');
    for (const secret of [state.providerEnv?.OPENAI_API_KEY, state.credentials.bot_token]) {
      if (secret) text = text.replaceAll(secret, '[redacted]');
    }
    return text.slice(0, 1200);
  };
  async function deliver(entry, text) {
    const parts = splitText(text);
    entry.replies = parts.map((content, index) => ({ content, client_id: 'cw-' + entry.id.slice(0, 32) + '-' + index, status: 'pending' }));
    await persist();
    for (const reply of entry.replies) {
      reply.status = 'attempting'; await persist();
      try {
        await api.send(state.credentials.ilink_user_id, entry.context, reply.content, reply.client_id);
        reply.status = 'sent'; await persist();
      } catch (error) {
        reply.status = 'unknown'; await persist(); log(safeError(error)); return;
      }
    }
  }
  async function drainOutbox() {
    if (outboxBusy || !state.context || !running) return;
    outboxBusy = true;
    try {
      const directory = path.join(dataDir, 'outbox');
      let files; try { files = await fs.readdir(directory); } catch { return; }
      for (const file of files.filter(name => /^[a-f0-9]{64}\.dpapi$/.test(name))) {
        const id = file.slice(0, -6); const receiptFile = path.join(directory, id + '.receipt.json');
        let reservation;
        try { reservation = await fs.open(receiptFile, 'wx'); }
        catch (error) { if (error.code === 'EEXIST') continue; throw error; }
        await reservation.writeFile(JSON.stringify({ status: 'in_flight' })); await reservation.close();
        const value = await store.load('outbox/' + id);
        let result = 'sent'; let deliveryError;
        try {
          if((value.files?.length||value.project_ref)&&!policyFor(state).capabilities.files)throw Error('FILE_ACCESS_DENIED');
          if(value.project_ref&&!value.files) {
            const importedEntry={id:value.id,context:value.context};
            const prepared=await prepareProjectResults({rpc,state,entry:importedEntry,text:'[[WECHAT_PROJECT_FILE:'+JSON.stringify(value.project_ref)+']]',persist});
            if(prepared.errors.length||!importedEntry.projectImports?.length)throw Error(prepared.errors[0]||'PROJECT_FILE_IMPORT_FAILED');
            const source=importedEntry.projectImports[0];const file=await validateLocalFile(path.join(state.cwd,source.local_copy));
            value.files=[{path:file.path,name:file.name,size:file.size,sha256:file.sha256}];
            await store.save(value,'outbox/'+id);
          }
          const text = [value.title, value.content].filter(Boolean).join('\n');
          const parts = text ? splitText(text) : [];
          for (let i = 0; i < parts.length; i++) {
            await api.send(state.credentials.ilink_user_id, state.context, parts[i], 'cw-notify-' + id.slice(0, 32) + '-' + i);
          }
          for (let i = 0; i < (value.images || []).length; i++) {
            await api.sendImage(state.credentials.ilink_user_id, state.context, value.images[i], 'cw-image-' + id.slice(0, 32) + '-' + i);
          }
          for (let i = 0; i < (value.files || []).length; i++) {
            await api.sendFile(state.credentials.ilink_user_id, value.context || state.context, value.files[i], 'cw-file-' + id.slice(0, 32) + '-' + i);
            state.lastFileSentAt = new Date().toISOString(); state.sentFileCount = (state.sentFileCount || 0) + 1;
          }
          if (!['file','question'].includes(value.kind)) state.latestNotification = text + (value.images?.length ? '\n[附图片]' : '');
          await persist();
        } catch (error) {
          deliveryError = safeError(error);
          result = value.kind === 'file' && (!error.fileSubmissionAttempted || /^WECHAT_(HTTP_4|API_)/.test(deliveryError)) ? 'failed' : 'unknown';
          log(deliveryError);
        }
        await fs.writeFile(receiptFile, JSON.stringify({ status: result, time: new Date().toISOString(), ...(deliveryError ? { error: deliveryError } : {}) }));
      }
    } finally { outboxBusy = false; }
  }
  async function control(entry) {
    const denial=deniedRequest(state,entry);
    if(denial){entry.status='blocked';await persist();await deliver(entry,denial);return true;}
    if((state.instanceId||'primary')==='primary') {
      const answerCommand=entry.text.match(/^\/回答\s+([a-f0-9]{12})\s+([\s\S]+)$/);
      const questionId=answerCommand?.[1],answer=answerCommand?.[2];
      if(questionId) {
        entry.status='control';await persist();
        try {
          const result=await questionBroker.resolve(questionId,answer,'wechat');
          await deliver(entry,result.won?'已收到你在微信对问题 '+result.question.short_id+' 的回复，正在同步给客户端。🐉':result.status==='answered'?'这个问题已收到'+(result.answer.channel==='desktop'?'客户端':'微信')+'的先到回复，已按那条回复处理，这条不会重复执行。':result.status==='expired'?'这个问题已过期，请让来源任务重新询问。':'先到的回复正在登记，暂不重复处理。');
        }catch(error){await deliver(entry,'这条问题回复未能登记：'+safeError(error));}
        return true;
      }
    }
    if (entry.text === '/状态') {
      entry.status = 'control'; await persist();
      await deliver(entry, busy ? '在线，GPT 小姐正在处理任务～工作安排会排队，闲聊可继续；回复 /停止 可中止当前任务。🐉' : attachmentBusy ? '在线，正在接收你上传的文件，普通聊天可继续。🐉' : '在线，GPT 小姐听着呢～可以发送文字、图片或文件。🐉');
    } else if (entry.text === '/停止') {
      entry.status = 'control'; await persist();
      const active = state.pending.find(e => e.status === 'running');
      if (active) { active.cancelRequested = true; await persist(); }
      if (active?.turnId) await rpc.request('turn/interrupt', { threadId: state.threadId, turnId: active.turnId });
      await deliver(entry, active ? '已请求停止当前任务。' : '当前没有正在执行的任务。');
    } else {
      const match = entry.text.match(/^\/(批准|拒绝|回答)\s+([a-f0-9]{6})(?:\s+([\s\S]+))?$/);
      if (!match) {
        if (!isControlMessage(entry.text)) return false;
        entry.status = 'control'; await persist();
        await deliver(entry, '控制命令格式不完整。可用 /状态、/停止，或 /批准 确认码、/拒绝 确认码、/回答 确认码 内容。');
        return true;
      }
      entry.status = 'control'; await persist();
      const approval = approvals.get(match[2]);
      if (!approval) { await deliver(entry, '这条确认请求不存在或已过期。'); return true; }
      if (approval.kind === 'input') {
        if (match[1] !== '回答' || !match[3]) { await deliver(entry, '请使用 /回答 ' + match[2] + ' 你的回答'); return true; }
        approval.resolve({ answers: { [approval.questionId]: { answers: [match[3]] } } });
      } else {
        if (!['批准', '拒绝'].includes(match[1])) { await deliver(entry, '请回复 /批准 或 /拒绝，后接确认码。'); return true; }
        approval.resolve({ decision: match[1] === '批准' ? 'accept' : 'decline' });
      }
      approvals.delete(match[2]); await deliver(entry, '已收到你的选择。');
    }
    return true;
  }
  async function onApproval(request) {
    const active = state.pending.find(e => e.status === 'running');
    if (!active) return undefined;
    const code = randomBytes(3).toString('hex');
    if (['item/commandExecution/requestApproval', 'item/fileChange/requestApproval'].includes(request.method)) {
      const description = redact(request.params?.command || request.params?.reason || request.params?.grantRoot || request.method);
      active.waitingForUser = true;
      const promise = new Promise(resolve => {
        const timer = setTimeout(() => { active.waitingForUser = false; approvals.delete(code); resolve({ decision: 'decline' }); }, 10 * 60 * 1000);
        approvals.set(code, { kind: 'approval', resolve: result => { active.waitingForUser = false; clearTimeout(timer); resolve(result); } });
      });
      await deliver({ id: digest('approval:' + code), context: state.context || active.context }, '操作需要你确认：\n' + description + '\n同意本次：/批准 ' + code + '\n拒绝：/拒绝 ' + code);
      return promise;
    }
    if (request.method === 'item/tool/requestUserInput' && request.params?.questions?.length === 1) {
      const question = request.params.questions[0];
      active.waitingForUser = true;
      const promise = new Promise(resolve => {
        const timer = setTimeout(() => { active.waitingForUser = false; approvals.delete(code); resolve({ answers: {} }); }, 10 * 60 * 1000);
        approvals.set(code, { kind: 'input', questionId: question.id, resolve: result => { active.waitingForUser = false; clearTimeout(timer); resolve(result); } });
      });
      const options = (question.options || []).map(item => item.label).join('；');
      await deliver({ id: digest('question:' + code), context: state.context || active.context },
        redact(question.question) + (options ? '\n选项：' + options : '') + '\n回复：/回答 ' + code + ' 你的回答');
      return promise;
    }
    await deliver({ id: digest('unsupported:' + code), context: state.context || active.context }, '当前操作需要一种尚未接入微信的交互，请在电脑端处理此任务。');
    return undefined;
  }
  async function processQueue() {
    if (!running || busy || unhealthy) return;
    const entry = state.pending.find(e => e.status === 'queued' && entryIntent(e, state) === 'work');
    if (!entry) return;
    const denial=deniedRequest(state,entry);if(denial){entry.status='blocked';await persist();await deliver(entry,denial);return;}
    if (state.pending.some(other => other !== entry && state.pending.indexOf(other) < state.pending.indexOf(entry) && other.files?.length && !other.filesReady)) return;
    busy = true;
    try {
      await acknowledgeEntry(api, state, entry, persist);
      entry.status = 'running'; await persist(); await meta('working');
      progress = new WorkProgress(entry, { persist, send: (text, id) => api.send(state.credentials.ilink_user_id, entry.context, redact(text), id) });
      await prepareFiles(entry);
      if (entry.fileErrors?.length) throw Error('FILE_ATTACHMENTS_INCOMPLETE');
      if (entry.images?.length) {
        if (entry.images.length > 4) throw new Error('TOO_MANY_IMAGES');
        entry.imagePaths = [];
        for (let i = 0; i < entry.images.length; i++) {
          entry.imagePaths.push(await downloadIncomingImage(api, entry.images[i], path.join(state.cwd, 'work', 'wechat-images'), entry.id, i));
        }
        await persist();
      }
      const result = entry.unsupported
        ? { status: 'completed', text: '目前支持文字、图片和文件；语音请先用文字说明要处理的内容。🐉' }
        : await agentTurn(rpc, state, entry, persist, onApproval, update => progress.update({ text: redact(update.text) }));
      const projectResult=await prepareProjectResults({rpc,state,entry,text:result.text,persist});
      const outgoing = await queueResultFiles({ state, store, dataDir, entry, text: projectResult.text });
      outgoing.errors.push(...projectResult.errors);
      let responseText = outgoing.text;
      if (outgoing.files.length) {
        progress.update({ text: '处理结果已生成，正在发送文件。' });
        await drainOutbox();
        const results = [];
        for (const file of outgoing.files) {
          let receipt; try { receipt = JSON.parse(await fs.readFile(path.join(dataDir,'outbox',file.event_hash+'.receipt.json'),'utf8')); } catch { }
          results.push(file.file_name + '：' + (receipt?.status === 'sent' ? '已提交文件发送' : receipt?.status === 'unknown' ? '发送结果未确认，不自动重发' : receipt?.status === 'failed' ? '文件发送失败' : '已排队发送'));
        }
        responseText += '\n\n文件：\n' + results.join('\n');
      }
      if (outgoing.errors.length) responseText += '\n\n部分文件未发送：' + outgoing.errors.join('、');
      await progress.close();
      entry.resultStatus = result.status; await persist();
      await deliver(entry, responseText || '处理完成。');
      entry.status = result.status;
      state.lastWorkResult = { status: result.status, text: responseText.slice(0, 1500), at: new Date().toISOString() };
    } catch (error) {
      entry.status = 'uncertain'; await persist(); log(safeError(error));
      await deliver(entry, '这次任务未能完整执行，请发新消息说明是否继续。错误类型：' + safeError(error) + (entry.attachments?.length ? '\n已保存的文件：' + entry.attachments.map(file => file.name).join('、') : '') + (entry.fileErrors?.length ? '\n未能接收：' + entry.fileErrors.map(file => file.name + '（' + file.error + '）').join('、') : ''));
      if (safeError(error).startsWith('CODEX_')) { unhealthy = true; running = false; }
    } finally {
      await progress?.close(); progress = null;
      state.pending = state.pending.filter(isPendingEntry);
      await persist(); busy = false; await meta(running ? 'listening' : 'stopping');
    }
  }
  async function prepareImages(entry) {
    if (!entry.images?.length || entry.imagePaths?.length) return;
    if (entry.images.length > 4) throw new Error('TOO_MANY_IMAGES');
    entry.imagePaths = [];
    for (let i = 0; i < entry.images.length; i++) entry.imagePaths.push(await downloadIncomingImage(api, entry.images[i], path.join(state.cwd, 'work', 'wechat-images'), entry.id, i));
  }
  async function prepareFiles(entry) {
    await receiveFileBatch(api, state, entry, persist);
  }
  async function processAttachmentQueue() {
    if(!running)return;
    if (attachmentBusy || !running) return;
    const entry = state.pending.find(item => item.status === 'queued' && entryIntent(item,state) === 'attachment');
    if (!entry) return;
    attachmentBusy = true; entry.status = 'receiving';
    try {
      await persist(); await prepareFiles(entry);
      const list = (entry.attachments || []).map(file => file.name + '（'+file.kind+'，'+file.size+' 字节）');
      const failures = (entry.fileErrors || []).map(file => file.name+'：'+file.error);
      await deliver(entry,(list.length ? '文件已保存：\n'+list.join('\n')+'\n\n你想让我怎么处理？可以接着说“分析刚才的文件”或“修改后把文件发回来”。' : '文件未能接收。')+(failures.length ? '\n\n未接收成功：\n'+failures.join('\n') : ''));
      entry.status = 'completed';
    } catch (error) { entry.status = 'uncertain'; await deliver(entry,'文件未能完整接收，错误类型：'+safeError(error)); }
    finally { attachmentBusy = false; state.pending = state.pending.filter(isPendingEntry); await persist(); await meta(busy?'working':'listening'); }
  }
  async function processChatQueue() {
    if(!running)return;
    if (chatBusy || !running) return;
    const entry = state.pending.find(e => e.status === 'queued' && entryIntent(e, state) === 'chat');
    if (!entry) return;
    chatBusy = true; entry.status = 'chatting'; chatController = new AbortController();
    try {
      await persist();
      await prepareImages(entry);
      const result = entry.unsupported ? { status: 'completed', text: '目前支持文字、图片和文件；语音请先用文字说明。🐉' }
        : await fastChat(state, entry, { nativeReply: (message, current) => nativeChat.reply(message, current, chatController.signal) });
      entry.resultStatus = result.status; await persist(); await deliver(entry, result.text); entry.status = result.status;
    } catch (error) {
      entry.status = 'uncertain'; await persist(); log(safeError(error));
      if (running) await deliver(entry, '这次聊天暂时没能正常返回，请再发一句话试试。');
    } finally {
      chatBusy = false; chatController = null;
      state.pending = state.pending.filter(isPendingEntry); await persist(); await meta(busy ? 'working' : 'listening');
    }
  }
  async function syncQuestionAnswers() {
    if((state.instanceId||'primary')!=='primary'||!running||questionSyncBusy||Date.now()-lastQuestionSync<5000)return;
    questionSyncBusy=true;lastQuestionSync=Date.now();
    try {
      for(const metadata of await questionBroker.list('answered')) {
        const receiptFile=path.join(questionDir,metadata.id+'.relay.receipt.json');
        try {await fs.access(receiptFile);continue;}catch(error){if(error.code!=='ENOENT')throw error;}
        const current=await questionBroker.status(metadata.id);
        if(current.answer?.channel!=='wechat')continue;
        const reserved=await fs.open(receiptFile,'wx');await reserved.writeFile(JSON.stringify({status:'in_flight'}));await reserved.close();
        let status='submitted';
        try {
          if(current.question.thread_id===state.threadId)status='same_thread_use_broker_status';
          else await callProjectTool(rpc,state,'send_message_to_thread',{threadId:current.question.thread_id,hostId:'local',prompt:'【微信助手：已收到用户回复】\n问题编号：'+current.question.short_id+'\n用户已通过ClawBot回答此问题：\n'+current.answer.answer+'\n\n这是用户在微信端对该问题的直接回答。先到答案已锁定；请读取微信助手question broker的status核对该编号。接下来必须同步完成客户端原生问题：用户已明确要求任一端回答后关闭原问题框并清除“需要用户输入”。使用可用的原生提交接口，或computer-use技能检查同编号的问题，将锁定答案回填并提交，验证问题框消失且侧栏等待输入标记消除；不要只发一条文字回执，不要点击跳过或取消来代替提交。不能操作其他编号的问题。若本机客户端无法访问，明确记录unconfirmed。完成验证后调用wechat-question.mjs ui-complete --id '+current.question.short_id+' --result submitted（已关闭则already_closed），再按锁定答案继续。不要重复执行既有任务，不要将本回执当成其他项目的新任务或扩大原问题授权。'});
        }catch{status='unconfirmed';}
        await fs.writeFile(receiptFile,JSON.stringify({status,time:new Date().toISOString()}));
      }
    }finally{questionSyncBusy=false;}
  }
  let watch;
  try {
    await rpc.initialize();
    const configuration = await rpc.request('config/read', { includeLayers: false });
    rpc.availableMcpServers=Object.keys(configuration.config.mcp_servers||{});
    await resumeWechatThread(rpc, state, () => store.save(state));
    try {
      const inventory=await rpc.request('mcpServerStatus/list',{threadId:state.threadId,serverName:'codex_app',detail:'toolsAndAuthOnly'},30000);
      rpc.projectToolsConnected=(inventory.data||[]).some(server=>server.name==='codex_app'&&server.runtimeStatus==='connected'&&server.tools?.send_message_to_thread);
    } catch {rpc.projectToolsConnected=false;log('PROJECT_APP_TOOLS_UNAVAILABLE');}
    nativeChat = new NativeChat(state, configuration.config);
    nativeChat.warmup().catch(() => { log('CHAT_WARMUP_FAILED'); });
    for (const entry of state.pending) {
      if ((['running','chatting','receiving'].includes(entry.status) || entry.replies?.some(reply => reply.status !== 'sent')) && !entry.recovery_notice) {
        entry.status = 'uncertain';
        entry.recovery_notice = 'attempting'; await persist();
        await deliver({ id: digest('recovery:' + entry.id), context: entry.context }, '服务曾中断，上次任务或微信回复的结果需要核实，没有自动重跑。请发新消息说明是否继续。');
      }
    }
    state.pending = state.pending.filter(entry => entry.status === 'queued');
    await persist(); await meta('listening');
    try { await api.request('/ilink/bot/msg/notifystart', { body: {} }); } catch { log('NOTIFY_START_UNCONFIRMED'); }
    watch = setInterval(async () => {
      try{
        const request=JSON.parse(await fs.readFile(idleStopFile,'utf8'));
        if(/^[a-f0-9]{32}$/.test(request.id)){
          const occupied=busy||chatBusy||attachmentBusy||state.pending.some(e=>['queued','running','chatting','receiving'].includes(e.status));
          if(!occupied)running=false;
          await fs.writeFile(path.join(dataDir,'idle-stop-'+request.id+'.json'),JSON.stringify({status:occupied?'busy':'accepted'}));
        }
        await fs.unlink(idleStopFile);
      }catch(error){if(error.code!=='ENOENT')log('IDLE_STOP_CHECK_FAILED');}
      try {
        await fs.access(stopFile); running = false;
        chatController?.abort();
        const active = state.pending.find(entry => entry.status === 'running');
        if (active) active.cancelRequested = true;
        if (active?.turnId) await rpc.request('turn/interrupt', { threadId: state.threadId, turnId: active.turnId });
      } catch { }
      if (!busy && running) processQueue().catch(() => { unhealthy = true; running = false; });
      if (!chatBusy && running) processChatQueue().catch(() => {});
      if (!attachmentBusy && running) processAttachmentQueue().catch(() => {});
      if (running) progress?.tick().catch(() => {});
      if (running) drainOutbox().catch(() => { unhealthy = true; running = false; });
      if (running) syncQuestionAnswers().catch(()=>{log('QUESTION_SYNC_UNCONFIRMED');});
      if(running&&!desktopCommandsBusy){desktopCommandsBusy=true;drainDesktopCommands({rpc,state,store,dataDir}).catch(()=>log('DESKTOP_ACTION_FAILED')).finally(()=>{desktopCommandsBusy=false;});}
    }, 500);
    let failures = 0;
    while (running) {
      try {
        const response = await api.updates(state.cursor, 45000);
        if(!running)continue;
        ingest(state, response); await persist(); failures = 0;
        for (const entry of [...state.pending]) {
          if (entry.status === 'queued') {
            if (!(await control(entry)) && entryIntent(entry, state) === 'work') acknowledgeEntry(api, state, entry, persist).catch(() => {});
          }
        }
        state.pending = state.pending.filter(isPendingEntry);
        await persist();
        await meta(busy ? 'working' : 'listening');
        processQueue().catch(() => { unhealthy = true; running = false; });
        processChatQueue().catch(() => {});
        processAttachmentQueue().catch(() => {});
        if (!(response.msgs?.length)) await sleep(100);
      } catch (error) {
        const code = safeError(error); log(code);
        if (code.includes('-14') || code === 'WECHAT_HTTP_401' || code === 'WECHAT_HTTP_403' || code === 'QUEUE_FULL' || code === 'SECURE_STORE_FAILED') {
          unhealthy = true; running = false; await meta('needs_attention'); break;
        }
        failures++; await sleep(Math.min(30000, 1000 * 2 ** Math.min(failures, 5)));
      }
    }
  } finally {
    running = false; clearInterval(watch);
    for (const approval of approvals.values()) approval.resolve(approval.kind === 'input' ? { answers: {} } : { decision: 'decline' });
    nativeChat?.close(); rpc.close();
    await meta(unhealthy ? 'needs_attention' : 'stopped');
    try { await fs.unlink(lockFile); } catch { }
    try { await fs.unlink(stopFile); } catch { }
  }
}

async function main() {
  if (process.platform !== 'win32') throw new Error('WINDOWS_REQUIRED');
  Object.assign(process.env,await desktopEnvironment(SecureStore,path.join(scriptDir,'secure-store.ps1')));
  if (command === 'prepare') return prepare();
  if (command === 'login') return login();
  if (command === 'smoke') return smoke();
  if (command === 'start') return start();
  if (command === 'run') return run();
  if (command === 'send') return enqueueNotification();
  if (command === 'send-image') return enqueueImage();
  if (command === 'send-file') return enqueueFile();
  if (command === 'send-project-file') return enqueueProjectFile();
  if (command === 'desktop-action') return desktopAction();
  if (command === 'image-test') return imageTest();
  if(command==='stop-idle'){
    const id=option('--request');if(!/^[a-f0-9]{32}$/.test(id||''))throw Error('INVALID_STOP_REQUEST');
    await fs.mkdir(dataDir,{recursive:true});await fs.writeFile(idleStopFile,JSON.stringify({id}));output({status:'idle_stop_requested',request_id:id});return;
  }
  if (command === 'stop') {
    await fs.mkdir(dataDir, { recursive: true }); await fs.writeFile(stopFile, 'stop');
    output({ status: 'stop_requested', detail: 'The listener exits after the current long poll; the active agent turn is interrupted.' }); return;
  }
  if (command === 'status') {
    const meta = await loadMeta();
    output({ ...meta, running: !!(meta.running && meta.pid && alive(meta.pid)) }); return;
  }
  throw new Error('UNKNOWN_COMMAND');
}
main().catch(error => { output({ status: 'error', code: safeError(error) }); process.exitCode = 1; });
