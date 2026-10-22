import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash,randomBytes} from 'node:crypto';

export const REPOSITORY='SakuraEdge/wechat-assistant';
export const LATEST_URL='https://api.github.com/repos/'+REPOSITORY+'/releases/latest';
const MAX_INSTALLER=250*1024*1024;
const headers={Accept:'application/vnd.github+json','User-Agent':'ClawBot-Instance-Manager'};
export function versionParts(value){const match=/^v?(0|[1-9]\d{0,8})\.(0|[1-9]\d{0,8})\.(0|[1-9]\d{0,8})$/.exec(value||'');if(!match)throw Error('UPDATE_VERSION_INVALID');return match.slice(1).map(Number);}
export function newer(left,right){const a=versionParts(left),b=versionParts(right);for(let i=0;i<3;i++)if(a[i]!==b[i])return a[i]>b[i];return false;}
function releaseUrl(tag){return 'https://github.com/'+REPOSITORY+'/releases/tag/'+tag;}
function validUrl(value,hosts){let url;try{url=new URL(value);}catch{throw Error('UPDATE_URL_REJECTED');}if(url.protocol!=='https:'||url.username||url.password||url.port||!hosts.includes(url.hostname))throw Error('UPDATE_URL_REJECTED');return url;}
async function bytes(response,maximum){
 const length=response.headers.get('content-length');if(length!==null&&(!/^\d+$/.test(length)||Number(length)>maximum))throw Error('UPDATE_TOO_LARGE');
 const chunks=[];let size=0;for await(const chunk of response.body){size+=chunk.length;if(size>maximum)throw Error('UPDATE_TOO_LARGE');chunks.push(chunk);}return Buffer.concat(chunks);
}
export function selectRelease(release,current){
 versionParts(current);
 if(!release||release.draft!==false||release.prerelease!==false||!release.published_at)throw Error('UPDATE_RELEASE_INVALID');
 const version=versionParts(release.tag_name).join('.'),tag='v'+version;
 if(release.tag_name!==tag||release.html_url!==releaseUrl(tag))throw Error('UPDATE_RELEASE_INVALID');
 const available=newer(version,current),base={status:'update_check',current_version:current,latest_version:version,available,url:releaseUrl(tag)};
 if(!available)return base;
 const name='ClawBot-Instance-Manager-Setup-'+version+'-windows-x64.exe';
 const matches=(release.assets||[]).filter(asset=>asset.name===name);
 if(matches.length!==1)throw Error('UPDATE_ASSET_MISSING');const asset=matches[0];
 if(asset.state!=='uploaded'||!Number.isSafeInteger(asset.size)||asset.size<=0||asset.size>MAX_INSTALLER||!/^sha256:[a-f0-9]{64}$/i.test(asset.digest||''))throw Error('UPDATE_ASSET_INVALID');
 const expected='https://github.com/'+REPOSITORY+'/releases/download/'+tag+'/'+name;
 if(asset.browser_download_url!==expected)throw Error('UPDATE_URL_REJECTED');
 return {...base,asset:{name,url:expected,size:asset.size,sha256:asset.digest.slice(7).toLowerCase()}};
}
export async function checkUpdate(current,{fetchImpl=fetch}={}){
 versionParts(current);
 let response;try{response=await fetchImpl(LATEST_URL,{headers,redirect:'error',signal:AbortSignal.timeout(20000)});}catch{throw Error('UPDATE_NETWORK_FAILED');}
 if(response.status===404)return {status:'update_check',current_version:current,latest_version:null,available:false,reason:'NO_PUBLISHED_RELEASE'};
 if([403,429].includes(response.status))return checkPublicRelease(current,fetchImpl);if(!response.ok)throw Error('UPDATE_NETWORK_FAILED');
 let release;try{release=JSON.parse((await bytes(response,1024*1024)).toString('utf8'));}catch{throw Error('UPDATE_RELEASE_INVALID');}
 return {...selectRelease(release,current),checked_at:new Date().toISOString()};
}
async function checkPublicRelease(current,fetchImpl){
 let response;try{response=await fetchImpl('https://github.com/'+REPOSITORY+'/releases/latest',{headers:{'User-Agent':headers['User-Agent']},redirect:'manual',signal:AbortSignal.timeout(20000)});}catch{throw Error('UPDATE_RATE_LIMITED');}
 if(![301,302,303,307,308].includes(response.status))throw Error('UPDATE_RATE_LIMITED');
 const destination=validUrl(response.headers.get('location'),['github.com']);
 const match=new RegExp('^/'+REPOSITORY+'/releases/tag/(v[0-9]+\\.[0-9]+\\.[0-9]+)$').exec(destination.pathname);
 if(!match||destination.search||destination.hash)throw Error('UPDATE_RELEASE_INVALID');
 const tag=match[1],version=versionParts(tag).join('.'),release={draft:false,prerelease:false,published_at:true,tag_name:tag,html_url:releaseUrl(tag),assets:[]};
 if(newer(version,current)){
  const name='ClawBot-Instance-Manager-Setup-'+version+'-windows-x64.exe',base='https://github.com/'+REPOSITORY+'/releases/download/'+tag+'/';
  const sums=(await bytes(await assetResponse(base+'SHA256SUMS.txt',fetchImpl),128*1024)).toString('utf8');
  const matching=sums.split(/\r?\n/).map(line=>line.trim().split(/\s+/)).filter(parts=>parts.length===2&&parts[1]===name&&/^[a-f0-9]{64}$/i.test(parts[0]));
  if(matching.length!==1)throw Error('UPDATE_ASSET_INVALID');
  const head=await assetResponse(base+name,fetchImpl,'HEAD'),size=Number(head.headers.get('content-length'));
  release.assets=[{name,state:'uploaded',size,digest:'sha256:'+matching[0][0],browser_download_url:base+name}];
 }
 return {...selectRelease(release,current),checked_at:new Date().toISOString(),source:'github-public-release'};
}
async function assetResponse(url,fetchImpl,method='GET'){
 let target=validUrl(url,['github.com']);
 for(let hop=0;hop<5;hop++){
  let response;try{response=await fetchImpl(target.href,{method,headers:{'User-Agent':headers['User-Agent']},redirect:'manual',signal:AbortSignal.timeout(120000)});}catch{throw Error('UPDATE_DOWNLOAD_FAILED');}
  if([301,302,303,307,308].includes(response.status)){target=validUrl(new URL(response.headers.get('location'),target).href,['github.com','release-assets.githubusercontent.com','objects.githubusercontent.com']);continue;}
  if(!response.ok)throw Error('UPDATE_DOWNLOAD_FAILED');return response;
 }
 throw Error('UPDATE_REDIRECT_LIMIT');
}
export async function updateDirectory(root,version){
 versionParts(version);await fs.mkdir(root,{recursive:true});const actual=await fs.realpath(root),directory=path.join(actual,version);
 await fs.mkdir(directory,{recursive:true});if((await fs.lstat(directory)).isSymbolicLink()||await fs.realpath(directory)!==directory)throw Error('UPDATE_PATH_REJECTED');return directory;
}
export async function verifyInstaller(file,asset,root){
 const actual=await fs.realpath(root),relative=path.relative(actual,file);
 if(relative.startsWith('..')||path.isAbsolute(relative)||path.basename(file)!==asset.name)throw Error('UPDATE_PATH_REJECTED');
 if((await fs.lstat(file)).isSymbolicLink()||await fs.realpath(file)!==file)throw Error('UPDATE_PATH_REJECTED');
 const stat=await fs.stat(file);if(!stat.isFile()||stat.size!==asset.size)throw Error('UPDATE_HASH_MISMATCH');
 const hash=createHash('sha256');const handle=await fs.open(file,'r');try{for await(const chunk of handle.createReadStream())hash.update(chunk);}finally{await handle.close();}
 if(hash.digest('hex')!==asset.sha256)throw Error('UPDATE_HASH_MISMATCH');return file;
}
export async function downloadUpdate(update,root,{fetchImpl=fetch}={}){
 if(!update.available||!update.asset)throw Error('UPDATE_NOT_AVAILABLE');
 const directory=await updateDirectory(root,update.latest_version),file=path.join(directory,update.asset.name);
 try{await verifyInstaller(file,update.asset,root);return {status:'update_downloaded',version:update.latest_version,file,bytes:update.asset.size};}catch(error){if(error.code!=='ENOENT'&&error.message==='UPDATE_PATH_REJECTED')throw error;}
 const temporary=path.join(directory,randomBytes(16).toString('hex')+'.part');let handle;
 try{
  const response=await assetResponse(update.asset.url,fetchImpl),length=response.headers.get('content-length');
  if(length!==null&&Number(length)!==update.asset.size)throw Error('UPDATE_SIZE_MISMATCH');
  handle=await fs.open(temporary,'wx');const hash=createHash('sha256');let size=0;
  for await(const chunk of response.body){size+=chunk.length;if(size>update.asset.size||size>MAX_INSTALLER)throw Error('UPDATE_SIZE_MISMATCH');hash.update(chunk);await handle.writeFile(chunk);}
  await handle.close();handle=null;if(size!==update.asset.size||hash.digest('hex')!==update.asset.sha256)throw Error('UPDATE_HASH_MISMATCH');
  if(await fs.lstat(file).then(stat=>stat.isSymbolicLink(),error=>{if(error.code==='ENOENT')return false;throw error;}))throw Error('UPDATE_PATH_REJECTED');
  await fs.rename(temporary,file);await verifyInstaller(file,update.asset,root);
  return {status:'update_downloaded',version:update.latest_version,file,bytes:size};
 }finally{if(handle)await handle.close();await fs.unlink(temporary).catch(error=>{if(error.code!=='ENOENT')throw error;});}
}
