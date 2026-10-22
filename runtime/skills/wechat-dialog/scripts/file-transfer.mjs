// FileItem wire format follows Tencent/openclaw-weixin src/api/types.ts and messaging/send.ts.
import fs from 'node:fs/promises';
import path from 'node:path';
import { randomBytes, createHash, createCipheriv, createDecipheriv } from 'node:crypto';
import { checkedMediaUrl, decodeImageKey } from './media.mjs';

export const FILE_TRANSFER_VERSION = 'wechat-files-v1';
export const MAX_FILE_BYTES = 100 * 1024 * 1024;
export const MAX_FILES_PER_MESSAGE = 4;
const CDN_BASE = 'https://novac2c.cdn.weixin.qq.com/c2c';
const hash = (bytes, algorithm = 'sha256') => createHash(algorithm).update(bytes).digest('hex');
const inside = (root, file) => { const rel = path.relative(root, file); return rel !== '..' && !rel.startsWith('..' + path.sep) && !path.isAbsolute(rel); };

export function safeFilename(value) {
  let name = typeof value === 'string' ? path.win32.basename(value.replaceAll('/', '\\')) : 'file.bin';
  name = name.normalize('NFC').replace(/[<>:"/\\|?*\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]/g, '_').replace(/^[.\s]+|[.\s]+$/g, '');
  if (!name) name = 'file.bin';
  if (/^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(name)) name = '_' + name;
  if (name.length > 100) { const ext = path.extname(name).slice(0, 20); name = name.slice(0, 100 - ext.length) + ext; }
  return name;
}
export function fileKind(name) {
  const extension = path.extname(name).toLowerCase();
  const kinds = { '.txt':'文本', '.md':'Markdown', '.json':'JSON', '.csv':'CSV 表格', '.pdf':'PDF 文档', '.docx':'Word 文档', '.doc':'Word 文档', '.xlsx':'Excel 表格', '.xls':'Excel 表格', '.pptx':'PowerPoint', '.ppt':'PowerPoint', '.zip':'ZIP 压缩包', '.7z':'7z 压缩包', '.rar':'RAR 压缩包', '.cpp':'C++ 源码', '.c':'C 源码', '.py':'Python 源码', '.js':'JavaScript 源码', '.ts':'TypeScript 源码', '.html':'HTML', '.png':'PNG 图片', '.jpg':'JPEG 图片', '.jpeg':'JPEG 图片', '.apk':'Android 安装包', '.exe':'Windows 程序' };
  return kinds[extension] || (extension ? extension.slice(1).toUpperCase() + ' 文件' : '文件');
}
function declaredSize(item) {
  if (item.len === undefined || item.len === null || item.len === '') return null;
  if (!/^[0-9]{1,20}$/.test(String(item.len))) throw Error('INVALID_FILE_LENGTH');
  const value = BigInt(item.len); if (value > BigInt(MAX_FILE_BYTES)) throw Error('FILE_TOO_LARGE');
  return Number(value);
}
async function boundedFileBytes(response) {
  if (Number(response.headers.get('content-length')) > MAX_FILE_BYTES + 16) throw Error('FILE_TOO_LARGE');
  const reader = response.body?.getReader(); if (!reader) throw Error('EMPTY_FILE_RESPONSE');
  const chunks = []; let total = 0;
  try { while (true) { const { value, done } = await reader.read(); if (done) break; total += value.byteLength;
    if (total > MAX_FILE_BYTES + 16) { await reader.cancel(); throw Error('FILE_TOO_LARGE'); } chunks.push(Buffer.from(value));
  } } finally { reader.releaseLock(); }
  return Buffer.concat(chunks, total);
}
async function saveAtomically(directory, filename, bytes) {
  await fs.mkdir(directory, { recursive: true });
  const realDirectory = await fs.realpath(directory);
  if (realDirectory.toLowerCase() !== path.resolve(directory).toLowerCase()) throw Error('FILE_DIRECTORY_LINK_REJECTED');
  const target = path.join(realDirectory, filename);
  if (target.length > 250) throw Error('FILE_PATH_TOO_LONG');
  try { const info = await fs.lstat(target); if (!info.isFile() || info.isSymbolicLink() || hash(await fs.readFile(target)) !== hash(bytes)) throw Error('FILE_TARGET_CONFLICT'); return target; }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  const temporary = target + '.' + randomBytes(4).toString('hex') + '.tmp';
  try { await fs.writeFile(temporary, bytes, { flag: 'wx', mode: 0o600 }); await fs.rename(temporary, target); }
  finally { try { await fs.unlink(temporary); } catch (error) { if (error.code !== 'ENOENT') throw error; } }
  return target;
}
export async function downloadIncomingFile(api, item, directory, messageId, index = 0) {
  if (!/^[a-f0-9]{64}$/.test(messageId) || !Number.isInteger(index) || index < 0 || index >= MAX_FILES_PER_MESSAGE) throw Error('INVALID_FILE_ID');
  const expected = declaredSize(item);
  if (item.md5 !== undefined && (typeof item.md5 !== 'string' || !/^[a-f0-9]{32}$/i.test(item.md5))) throw Error('INVALID_FILE_MD5');
  const media = item.media;
  if (!media || (!media.full_url && !media.encrypt_query_param)) throw Error('MISSING_FILE_REFERENCE');
  if (media.encrypt_type !== undefined && media.encrypt_type !== 1) throw Error('UNSUPPORTED_FILE_ENCRYPTION');
  const key = decodeImageKey({ media }); if (!key) throw Error('MISSING_FILE_KEY');
  const url = checkedMediaUrl(media.full_url || CDN_BASE + '/download?encrypted_query_param=' + encodeURIComponent(media.encrypt_query_param));
  const response = await api.fetch(url, { redirect: 'error', signal: AbortSignal.timeout(120000) });
  if (!response.ok) throw Error('FILE_DOWNLOAD_HTTP_' + response.status);
  let bytes = await boundedFileBytes(response);
  try { const decipher = createDecipheriv('aes-128-ecb', key, null); bytes = Buffer.concat([decipher.update(bytes), decipher.final()]); }
  catch { throw Error('FILE_DECRYPT_FAILED'); }
  if (bytes.length > MAX_FILE_BYTES) throw Error('FILE_TOO_LARGE');
  if (expected !== null && bytes.length !== expected) throw Error('FILE_LENGTH_MISMATCH');
  if (item.md5 && hash(bytes, 'md5') !== item.md5.toLowerCase()) throw Error('FILE_MD5_MISMATCH');
  const name = safeFilename(item.file_name);
  const filename = await saveAtomically(path.join(directory, messageId), index + '-' + name, bytes);
  return { path: filename, name, size: bytes.length, sha256: hash(bytes), kind: fileKind(name), message_id: messageId, received_at: new Date().toISOString() };
}
export async function validateLocalFile(filename) {
  const resolved = await fs.realpath(filename); const info = await fs.stat(resolved);
  if (!info.isFile()) throw Error('FILE_NOT_REGULAR');
  if (info.size > MAX_FILE_BYTES) throw Error('FILE_TOO_LARGE');
  const bytes = await fs.readFile(resolved); if (bytes.length > MAX_FILE_BYTES) throw Error('FILE_TOO_LARGE');
  return { path: resolved, name: safeFilename(path.basename(resolved)), size: bytes.length, sha256: hash(bytes), bytes };
}
export async function receiveFileBatch(api, state, entry, persist) {
  if (!entry.files?.length || entry.filesReady) return;
  if (entry.files.length > MAX_FILES_PER_MESSAGE) throw Error('TOO_MANY_FILES');
  entry.attachments ||= []; entry.fileErrors = [];
  for (let i = 0; i < entry.files.length; i++) {
    if (entry.attachments.some(file => file.index === i)) continue;
    try {
      const file = { ...await downloadIncomingFile(api, entry.files[i], path.join(state.cwd,'work','wechat-files'),entry.id,i), index:i };
      entry.attachments.push(file); state.recentFiles = [...(state.recentFiles || []).filter(other => other.path !== file.path), file].slice(-20);
      state.lastFileReceivedAt = file.received_at; state.receivedFileCount = (state.receivedFileCount || 0) + 1;
    } catch (error) { entry.fileErrors.push({ name: '附件 ' + (i+1), error: /^[A-Z][A-Z0-9_-]*$/.test(error.message||'') ? error.message : 'FILE_LOCAL_OPERATION_FAILED' }); }
    await persist();
  }
  entry.filesReady = true; await persist();
}
export async function freezeOutgoingFile(filename, directory, id, displayName) {
  if (!/^[a-f0-9]{64}$/.test(id)) throw Error('INVALID_FILE_ID');
  const file = await validateLocalFile(filename); const name = safeFilename(displayName || file.name);
  const frozen = await saveAtomically(path.join(directory, id), name, file.bytes);
  return { path: frozen, name, size: file.size, sha256: file.sha256 };
}
export async function uploadWechatFile(api, filename, owner, expected = {}) {
  const file = await validateLocalFile(filename);
  if (expected.sha256 && file.sha256 !== expected.sha256) throw Error('OUTGOING_FILE_CHANGED');
  const key = randomBytes(16); const cipher = createCipheriv('aes-128-ecb', key, null);
  const encrypted = Buffer.concat([cipher.update(file.bytes), cipher.final()]); const filekey = randomBytes(16).toString('hex');
  const upload = await api.request('/ilink/bot/getuploadurl', { body: { filekey, media_type: 3, to_user_id: owner,
    rawsize: file.size, rawfilemd5: hash(file.bytes, 'md5'), filesize: encrypted.length, no_need_thumb: true, aeskey: key.toString('hex') } });
  if (!upload.upload_full_url && !upload.upload_param) throw Error('MISSING_FILE_UPLOAD_URL');
  const url = checkedMediaUrl(upload.upload_full_url || CDN_BASE + '/upload?encrypted_query_param=' + encodeURIComponent(upload.upload_param) + '&filekey=' + filekey);
  const response = await api.fetch(url, { method: 'POST', headers: { 'Content-Type':'application/octet-stream' }, body: encrypted, redirect: 'error', signal: AbortSignal.timeout(120000) });
  if (response.status !== 200) throw Error('FILE_UPLOAD_HTTP_' + response.status);
  const parameter = response.headers.get('x-encrypted-param'); if (!parameter) throw Error('MISSING_FILE_DOWNLOAD_PARAMETER');
  return { type: 4, file_item: { media: { encrypt_query_param: parameter, aes_key: Buffer.from(key.toString('hex')).toString('base64'), encrypt_type: 1 }, file_name: safeFilename(expected.name || file.name), len: String(file.size) } };
}
export async function outputsArtifact(workspace, relative) {
  if (typeof relative !== 'string' || !relative || /[\r\n\x00]/.test(relative) || path.win32.isAbsolute(relative) || path.posix.isAbsolute(relative)) throw Error('FILE_OUTSIDE_OUTPUTS');
  const normalized = relative.replaceAll('\\','/');
  if (!normalized.startsWith('outputs/') || normalized.split('/').some(part => part === '..' || part === '.')) throw Error('FILE_OUTSIDE_OUTPUTS');
  const realWorkspace = await fs.realpath(workspace); const realOutputs = await fs.realpath(path.join(workspace,'outputs'));
  const file = await fs.realpath(path.resolve(workspace, relative));
  if (!inside(realWorkspace,realOutputs) || !inside(realOutputs,file)) throw Error('FILE_OUTSIDE_OUTPUTS');
  return (await validateLocalFile(file)).path;
}
export function extractFileMarkers(text) {
  const names=[];
  const cleaned=text.replace(/\[\[WECHAT_FILE:([^\]\r\n]{1,500})\]\]/g,(_all,name)=>{if(!names.some(value=>value.toLowerCase()===name.trim().toLowerCase()))names.push(name.trim());return '';}).trim();
  if (names.length > MAX_FILES_PER_MESSAGE) throw Error('TOO_MANY_OUTGOING_FILES');
  return { text:cleaned, files:names };
}
export function attachmentContext(state, entry) {
  if (entry.attachments?.length) return entry.attachments;
  if (!/(文件|附件|刚才|刚刚|这个|代码|报告|压缩包|项目|文档|上一个)/.test(entry.text||'')) return [];
  const recent=state.recentFiles||[];const last=recent.at(-1);if(!last)return [];
  const named=recent.filter(file=>(entry.text||'').toLowerCase().includes(file.name.toLowerCase()));
  return (named.length?named:recent.filter(file=>file.message_id===last.message_id)).slice(-MAX_FILES_PER_MESSAGE);
}
