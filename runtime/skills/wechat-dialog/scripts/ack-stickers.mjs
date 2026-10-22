import fs from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { uploadWechatImage } from './media.mjs';
import {recordMessage} from './conversation-log.mjs';

export const ACK_STICKER_VERSION = 'persona-sticker-ack-v1';
const inFlight = new WeakMap();
const definiteFailure = error => /^WECHAT_(HTTP_4|API_)/.test(error.message || '');

async function selectSticker(cwd, queued) {
  const directory = path.join(cwd, 'outputs', 'persona');
  let config;
  try { config = JSON.parse(await fs.readFile(path.join(directory, 'ack-config.json'), 'utf8')); }
  catch (error) { if (error.code === 'ENOENT') return null; throw new Error('ACK_STICKER_CONFIG_INVALID'); }
  if (config.enabled !== true) return null;
  const name = queued ? config.queued : config.normal;
  if (typeof name !== 'string' || !/^[a-z0-9][a-z0-9-]*\.png$/.test(name)) throw new Error('ACK_STICKER_PATH_REJECTED');
  const root = await fs.realpath(path.join(directory, 'stickers'));
  const target = path.join(root, name);
  const info = await fs.lstat(target);
  if (!info.isFile() || info.isSymbolicLink() || info.size > 5 * 1024 * 1024) throw new Error('ACK_STICKER_FILE_REJECTED');
  const real = await fs.realpath(target);
  if (path.dirname(real).toLowerCase() !== root.toLowerCase()) throw new Error('ACK_STICKER_PATH_REJECTED');
  const bytes = await fs.readFile(real);
  if (!bytes.subarray(0, 8).equals(Buffer.from('89504e470d0a1a0a', 'hex'))) throw new Error('ACK_STICKER_FORMAT_REJECTED');
  const fingerprint = createHash('sha256').update(bytes).digest('hex');
  const manifest = JSON.parse(await fs.readFile(path.join(directory, 'manifest.json'), 'utf8'));
  if (!manifest.stickers?.some(item => item.file === 'stickers/' + name && item.sha256 === fingerprint)) {
    throw new Error('ACK_STICKER_NOT_IN_MANIFEST');
  }
  const ttl = Number.isFinite(config.cache_ttl_ms) ? Math.max(1000, Math.min(config.cache_ttl_ms, 3600000)) : 1800000;
  return { filename: real, fingerprint, ttl };
}

export async function sendAckSticker(api, state, entry, queued, persist, options = {}) {
  if(state.persona?.builtin_appearance===false)return;
  if (inFlight.has(entry)) return inFlight.get(entry);
  if (entry.ack?.status !== 'sent' || entry.ack.image_status) return;
  entry.ack.image_status = 'preparing';
  entry.ack.image_client_id = 'cw-ack-img-' + entry.id.slice(0, 32);
  const sending = (async () => {
    let attempted = false, fingerprint;
    try {
      await persist();
      const asset = await selectSticker(state.cwd, queued);
      if (!asset) { entry.ack.image_status = 'disabled'; await persist(); return; }
      fingerprint = asset.fingerprint;
      const now = (options.now || Date.now)();
      state.ackStickerCache ||= {};
      let cached = state.ackStickerCache[fingerprint];
      if (!cached || now - cached.createdAt >= asset.ttl) {
        const item = await (options.upload || uploadWechatImage)(api, asset.filename, state.credentials.ilink_user_id);
        cached = { item, createdAt: now };
        state.ackStickerCache[fingerprint] = cached;
        const newest = Object.entries(state.ackStickerCache).sort((a, b) => b[1].createdAt - a[1].createdAt).slice(0, 4);
        state.ackStickerCache = Object.fromEntries(newest);
        await persist();
      }
      entry.ack.image_status = 'attempting';
      await persist();
      attempted = true;
      await api.sendItems(state.credentials.ilink_user_id, entry.context, [cached.item], entry.ack.image_client_id);
      recordMessage(state,{id:'out-'+entry.ack.image_client_id,role:'assistant',text:'[工作回执表情图]',at:new Date().toISOString(),delivery:'sent',attachments:[{kind:'image',name:'工作回执表情图.png'}]});
      entry.ack.image_status = 'sent';
      state.lastAckImageAt = new Date(now).toISOString();
    } catch (error) {
      entry.ack.image_status = attempted && !definiteFailure(error) ? 'unknown' : 'failed';
      if (fingerprint && definiteFailure(error)) delete state.ackStickerCache?.[fingerprint];
    }
    await persist();
  })();
  inFlight.set(entry, sending);
  try { await sending; } finally { inFlight.delete(entry); }
}
