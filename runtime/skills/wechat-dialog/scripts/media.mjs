// Wire formats follow Tencent/openclaw-weixin docs/protocol.md and src/cdn/.
import fs from 'node:fs/promises';
import path from 'node:path';
import { randomBytes, createHash, createCipheriv, createDecipheriv } from 'node:crypto';

export const MAX_IMAGE_BYTES = 20 * 1024 * 1024;
const CDN_BASE = 'https://novac2c.cdn.weixin.qq.com/c2c';

export function checkedMediaUrl(value) {
  let url;
  try { url = new URL(value); } catch { throw new Error('INVALID_MEDIA_URL'); }
  if (url.protocol !== 'https:' || url.username || url.password || url.port ||
      !(url.hostname === 'cdn.weixin.qq.com' || url.hostname.endsWith('.cdn.weixin.qq.com'))) {
    throw new Error('UNTRUSTED_MEDIA_HOST');
  }
  return url.href;
}

export function imageExtension(bytes) {
  if (bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) return 'png';
  if (bytes.length >= 3 && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255) return 'jpg';
  if (/^GIF8[79]a$/.test(bytes.subarray(0, 6).toString('ascii'))) return 'gif';
  if (bytes.subarray(0, 4).toString('ascii') === 'RIFF' && bytes.subarray(8, 12).toString('ascii') === 'WEBP') return 'webp';
  throw new Error('UNSUPPORTED_IMAGE_FORMAT');
}

export function decodeImageKey(image) {
  if (image.aeskey) {
    if (typeof image.aeskey !== 'string' || !/^[a-f0-9]{32}$/i.test(image.aeskey)) throw new Error('INVALID_IMAGE_KEY');
    return Buffer.from(image.aeskey, 'hex');
  }
  const encoded = image.media?.aes_key;
  if (!encoded) return null;
  if (typeof encoded !== 'string' || !/^[A-Za-z0-9+/]+={0,2}$/.test(encoded)) throw new Error('INVALID_IMAGE_KEY');
  const bytes = Buffer.from(encoded, 'base64');
  if (bytes.length === 16) return bytes;
  if (bytes.length === 32 && /^[a-f0-9]{32}$/i.test(bytes.toString('ascii'))) return Buffer.from(bytes.toString('ascii'), 'hex');
  throw new Error('INVALID_IMAGE_KEY');
}

async function boundedBytes(response, limit) {
  if (Number(response.headers.get('content-length')) > limit) throw new Error('IMAGE_TOO_LARGE');
  const reader = response.body?.getReader();
  if (!reader) throw new Error('EMPTY_IMAGE_RESPONSE');
  const chunks = []; let total = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > limit) { await reader.cancel(); throw new Error('IMAGE_TOO_LARGE'); }
      chunks.push(Buffer.from(value));
    }
  } finally { reader.releaseLock(); }
  return Buffer.concat(chunks, total);
}

export async function downloadIncomingImage(api, image, directory, messageId, index = 0) {
  if (!/^[a-f0-9]{64}$/.test(messageId) || !Number.isInteger(index) || index < 0 || index > 3) throw new Error('INVALID_IMAGE_ID');
  const media = image?.media;
  if (!media || (!media.full_url && !media.encrypt_query_param)) throw new Error('MISSING_IMAGE_REFERENCE');
  if (media.encrypt_type !== undefined && media.encrypt_type !== 1) throw new Error('UNSUPPORTED_IMAGE_ENCRYPTION');
  const url = checkedMediaUrl(media.full_url || CDN_BASE + '/download?encrypted_query_param=' + encodeURIComponent(media.encrypt_query_param));
  const key = decodeImageKey(image);
  const response = await api.fetch(url, { redirect: 'error', signal: AbortSignal.timeout(45000) });
  if (!response.ok) {
    const detail = (response.headers.get('x-error-message') || '') + ' ' + (await response.text()).slice(0, 2000);
    const error = new Error('IMAGE_DOWNLOAD_HTTP_' + response.status);
    error.diagnosticHints = ['invalid', 'expired', 'signature', 'permission', 'not found', 'param', 'request', 'decrypt', 'fileid']
      .filter(word => detail.toLowerCase().includes(word));
    throw error;
  }
  let bytes = await boundedBytes(response, MAX_IMAGE_BYTES + 16);
  if (key) {
    try {
      const decipher = createDecipheriv('aes-128-ecb', key, null);
      bytes = Buffer.concat([decipher.update(bytes), decipher.final()]);
    } catch { throw new Error('IMAGE_DECRYPT_FAILED'); }
  }
  if (!bytes.length || bytes.length > MAX_IMAGE_BYTES) throw new Error('IMAGE_TOO_LARGE');
  const extension = imageExtension(bytes);
  await fs.mkdir(directory, { recursive: true });
  const target = path.join(directory, messageId + '-' + index + '.' + extension);
  await fs.writeFile(target, bytes, { mode: 0o600 });
  return target;
}

export async function validateLocalImage(filename) {
  const resolved = await fs.realpath(filename);
  const stat = await fs.stat(resolved);
  if (!stat.isFile() || !stat.size || stat.size > MAX_IMAGE_BYTES) throw new Error('IMAGE_TOO_LARGE');
  const bytes = await fs.readFile(resolved);
  imageExtension(bytes);
  return { path: resolved, bytes };
}

export async function uploadWechatImage(api, filename, owner) {
  const { bytes } = await validateLocalImage(filename);
  const key = randomBytes(16);
  const cipher = createCipheriv('aes-128-ecb', key, null);
  const encrypted = Buffer.concat([cipher.update(bytes), cipher.final()]);
  const filekey = randomBytes(16).toString('hex');
  const upload = await api.request('/ilink/bot/getuploadurl', { body: {
    filekey, media_type: 1, to_user_id: owner, rawsize: bytes.length,
    rawfilemd5: createHash('md5').update(bytes).digest('hex'), filesize: encrypted.length,
    no_need_thumb: true, aeskey: key.toString('hex')
  } });
  if (!upload.upload_full_url && !upload.upload_param) throw new Error('MISSING_IMAGE_UPLOAD_URL');
  const url = checkedMediaUrl(upload.upload_full_url || CDN_BASE + '/upload?encrypted_query_param=' +
    encodeURIComponent(upload.upload_param) + '&filekey=' + filekey);
  const response = await api.fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/octet-stream' },
    body: encrypted, redirect: 'error', signal: AbortSignal.timeout(60000) });
  if (response.status !== 200) throw new Error('IMAGE_UPLOAD_HTTP_' + response.status);
  const parameter = response.headers.get('x-encrypted-param');
  if (!parameter) throw new Error('MISSING_IMAGE_DOWNLOAD_PARAMETER');
  return { type: 2, image_item: { media: {
    encrypt_query_param: parameter, aes_key: Buffer.from(key.toString('hex')).toString('base64'), encrypt_type: 1
  }, mid_size: encrypted.length } };
}
