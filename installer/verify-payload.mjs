import fs from 'node:fs/promises';import path from 'node:path';import {createHash} from 'node:crypto';import {fileURLToPath} from 'node:url';
export async function verifyPayload(root){
 const base=await fs.realpath(root);const manifest=JSON.parse(await fs.readFile(path.join(base,'install-manifest.json'),'utf8'));
 if(manifest.schema!==1||!Array.isArray(manifest.files)||!manifest.files.length)throw Error('INVALID_INSTALL_MANIFEST');
 const seen=new Set();for(const item of manifest.files){
  if(typeof item.path!=='string'||/[\\:\x00-\x1f]/.test(item.path)||item.path.split('/').some(p=>!p||p==='.'||p==='..')||path.isAbsolute(item.path)||! /^[a-f0-9]{64}$/.test(item.sha256)||seen.has(item.path))throw Error('INVALID_MANIFEST_PATH');
  seen.add(item.path);const file=await fs.realpath(path.join(base,item.path));const rel=path.relative(base,file);if(rel.startsWith('..'+path.sep)||path.isAbsolute(rel))throw Error('INSTALL_PATH_ESCAPE');
  const data=await fs.readFile(file);if(data.length!==item.bytes||createHash('sha256').update(data).digest('hex')!==item.sha256)throw Error('INSTALL_HASH_MISMATCH');
 }
 return {status:'verified',version:manifest.version,files:seen.size};
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{console.log(JSON.stringify(await verifyPayload(process.argv[2]||path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'))));}
 catch(error){console.log(JSON.stringify({status:'error',code:/^[A-Z_]+$/.test(error.message)?error.message:'INSTALL_VERIFICATION_FAILED'}));process.exitCode=1;}
}
