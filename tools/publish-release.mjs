import fs from 'node:fs/promises';import path from 'node:path';import {fileURLToPath} from 'node:url';import {createHash} from 'node:crypto';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),repository='SakuraEdge/wechat-assistant';
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
export async function publishRelease({token,commit,progress=()=>{}}){
 if(!token||!/^[a-f0-9]{40}$/.test(commit||''))throw Error('TOKEN_AND_PUSHED_COMMIT_REQUIRED');
 const {version}=JSON.parse(await fs.readFile(path.join(root,'package.json'),'utf8')),tag='v'+version;
 const api=async(endpoint,{method='GET',body}={})=>{const response=await fetch('https://api.github.com'+endpoint,{method,headers:{Authorization:'Bearer '+token,Accept:'application/vnd.github+json','User-Agent':'ClawBot-Release',...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(45000)});const value=await response.json();if(!response.ok)throw Error('RELEASE_API_'+response.status);return value;};
 const repo=await api('/repos/'+repository);if(repo.private||repo.full_name!==repository)throw Error('PUBLIC_REPOSITORY_REQUIRED');
 const remote=await api('/repos/'+repository+'/commits/main');if(remote.sha!==commit)throw Error('PUSHED_COMMIT_MISMATCH');
 const directory=path.join(root,'dist','release-'+tag),names=['ClawBot-Instance-Manager-Setup-'+version+'-windows-x64.exe','ClawBot-Instance-Manager-'+version+'-windows-x64-portable.zip','SHA256SUMS.txt','install-manifest.json'];
 const assets=[];for(const name of names){const data=await fs.readFile(path.join(directory,name));assets.push({name,data,sha256:hash(data),bytes:data.length});}
 const sums=assets.find(x=>x.name==='SHA256SUMS.txt').data.toString('utf8');for(const asset of assets.slice(0,2))if(!sums.includes(asset.sha256+'  '+asset.name))throw Error('LOCAL_CHECKSUM_MISMATCH');
 const manifest=JSON.parse(assets.find(x=>x.name==='install-manifest.json').data.toString('utf8'));if(manifest.version!==version||manifest.platform!=='windows-x64')throw Error('INSTALL_MANIFEST_VERSION_MISMATCH');
 const body=await fs.readFile(path.join(root,'docs','release-'+tag+'.md'),'utf8');
 let release=(await api('/repos/'+repository+'/releases?per_page=100')).find(x=>x.tag_name===tag);
 if(release&&!release.draft){for(const asset of assets){const remoteAsset=release.assets.find(x=>x.name===asset.name);if(remoteAsset?.digest!=='sha256:'+asset.sha256||remoteAsset.size!==asset.bytes)throw Error('PUBLISHED_RELEASE_IS_IMMUTABLE');}return {status:'already_published',url:release.html_url,tag,commit};}
 if(release&&release.target_commitish!==commit)throw Error('DRAFT_TARGET_MISMATCH');
 if(!release){release=await api('/repos/'+repository+'/releases',{method:'POST',body:{tag_name:tag,target_commitish:commit,name:'ClawBot实例管理器 '+tag+' · Windows 一键安装版',body,draft:true,prerelease:false}});progress({status:'draft_created',id:release.id,tag});}
 const uploadBase=new URL(release.upload_url.replace(/\{.*$/,''));if(uploadBase.origin!=='https://uploads.github.com'||!uploadBase.pathname.startsWith('/repos/'+repository+'/'))throw Error('INVALID_ASSET_UPLOAD_URL');
 async function binary(url,authenticated){
  let response=await fetch(url,{headers:authenticated?{Authorization:'Bearer '+token,Accept:'application/octet-stream','User-Agent':'ClawBot-Release'}:{'User-Agent':'ClawBot-Release'},redirect:'manual',signal:AbortSignal.timeout(180000)});
  if([301,302,303,307,308].includes(response.status)){const target=new URL(response.headers.get('location'));if(target.protocol!=='https:'||!['release-assets.githubusercontent.com','objects.githubusercontent.com','github.com'].includes(target.hostname))throw Error('UNTRUSTED_ASSET_DOWNLOAD_HOST');response=await fetch(target,{headers:{'User-Agent':'ClawBot-Release'},signal:AbortSignal.timeout(180000)});}
  if(!response.ok)throw Error('ASSET_DOWNLOAD_FAILED');return Buffer.from(await response.arrayBuffer());
 }
 let uploaded=await api('/repos/'+repository+'/releases/'+release.id+'/assets?per_page=100');
 for(const asset of assets){
  let existing=uploaded.find(x=>x.name===asset.name);
  if(!existing){progress({status:'uploading',name:asset.name,bytes:asset.bytes});const url=new URL(uploadBase);url.searchParams.set('name',asset.name);const response=await fetch(url,{method:'POST',headers:{Authorization:'Bearer '+token,Accept:'application/vnd.github+json','User-Agent':'ClawBot-Release','Content-Type':asset.name.endsWith('.exe')?'application/vnd.microsoft.portable-executable':asset.name.endsWith('.zip')?'application/zip':'application/octet-stream','Content-Length':String(asset.bytes)},body:asset.data,signal:AbortSignal.timeout(240000)});if(response.status!==201)throw Error('ASSET_UPLOAD_UNCONFIRMED');existing=await response.json();}
  if(existing.state!=='uploaded'||existing.size!==asset.bytes||existing.digest!=='sha256:'+asset.sha256)throw Error('REMOTE_ASSET_HASH_MISMATCH');
  if(hash(await binary(existing.url,true))!==asset.sha256)throw Error('DOWNLOADED_ASSET_HASH_MISMATCH');
  progress({status:'asset_verified',name:asset.name,bytes:asset.bytes});
 }
 release=await api('/repos/'+repository+'/releases/'+release.id,{method:'PATCH',body:{draft:false,make_latest:'true'}});
 if(release.draft||!release.published_at)throw Error('RELEASE_PUBLICATION_UNCONFIRMED');
 const reference=await api('/repos/'+repository+'/git/ref/tags/'+tag);let target=reference.object;for(let i=0;target.type==='tag'&&i<3;i++)target=(await api('/repos/'+repository+'/git/tags/'+target.sha)).object;if(target.type!=='commit'||target.sha!==commit)throw Error('RELEASE_TAG_COMMIT_MISMATCH');
 const installer=release.assets.find(x=>x.name===assets[0].name);if(hash(await binary(installer.browser_download_url,false))!==assets[0].sha256)throw Error('PUBLIC_DOWNLOAD_HASH_MISMATCH');
 return {status:'published',tag,commit,url:release.html_url,public_download_verified:true,assets:release.assets.map(x=>({name:x.name,url:x.browser_download_url,bytes:x.size,sha256:x.digest})),published_at:release.published_at};
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{if(!process.argv.includes('--publish'))throw Error('EXPLICIT_PUBLISH_REQUIRED');const index=process.argv.indexOf('--commit');const result=await publishRelease({token:process.env.GITHUB_TOKEN,commit:process.argv[index+1],progress:value=>console.log(JSON.stringify(value))});console.log(JSON.stringify(result));}
 catch(error){console.log(JSON.stringify({status:'error',code:/^[A-Z0-9_]+$/.test(error.message)?error.message:'RELEASE_RESULT_UNCONFIRMED'}));process.exitCode=1;}
}
