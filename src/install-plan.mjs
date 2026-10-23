import fs from 'node:fs/promises';import path from 'node:path';import {newer} from './updates.mjs';
async function exists(file){try{return (await fs.stat(file)).isFile();}catch(e){if(e.code==='ENOENT')return false;throw e;}}
async function read(file){try{return JSON.parse(await fs.readFile(file,'utf8'));}catch(e){if(e.code==='ENOENT')return null;throw Error('UPDATE_TARGET_UNRECOGNIZED');}}
async function canonical(directory){let cursor=path.resolve(directory),tail=[];for(;;){try{return path.join(await fs.realpath(cursor),...tail.reverse());}catch(e){if(e.code!=='ENOENT')throw e;const parent=path.dirname(cursor);if(parent===cursor)throw e;tail.push(path.basename(cursor));cursor=parent;}}}
function overlaps(left,right){const inside=(a,b)=>{const rel=path.relative(a,b);return rel===''||!rel.startsWith('..'+path.sep)&&rel!=='..'&&!path.isAbsolute(rel);};return inside(left,right)||inside(right,left);}
export async function isInstalled(root,version){const manifest=await read(path.join(root,'install-manifest.json'));return !!(manifest?.platform==='windows-x64'&&manifest.version===version&&await exists(path.join(root,'unins000.exe')));}
export async function installationPlan(root,currentVersion,latestVersion,{defaultDirectory}={}){
 const source=await canonical(root);
 if(await isInstalled(source,currentVersion))return {can_install:true,installed:true,installation_mode:'update',install_directory:source};
 if(!defaultDirectory||!path.isAbsolute(defaultDirectory))throw Error('UPDATE_INSTALL_LOCATION_FAILED');
 let directory=await canonical(defaultDirectory);
 if(overlaps(source,directory))directory=await canonical(defaultDirectory+'-Installed');
 if(overlaps(source,directory))throw Error('UPDATE_SOURCE_OVERLAP');
 let entries;try{entries=await fs.readdir(directory);}catch(e){if(e.code!=='ENOENT')throw e;entries=[];}
 if(entries.length){
  const pkg=await read(path.join(directory,'package.json'));
  if(pkg?.name!=='wechat-assistant-manager'||!await isInstalled(directory,pkg.version))throw Error('UPDATE_TARGET_UNRECOGNIZED');
  if(newer(pkg.version,latestVersion))throw Error('UPDATE_TARGET_NEWER');
 }
 return {can_install:true,installed:false,installation_mode:'install',install_directory:directory};
}
