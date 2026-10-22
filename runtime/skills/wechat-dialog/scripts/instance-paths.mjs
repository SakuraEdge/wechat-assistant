import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const registration=/^[a-z][a-z0-9-]{0,47}\.json$/;
export async function instancePaths(env=process.env) {
  if(!env.LOCALAPPDATA||!path.isAbsolute(env.LOCALAPPDATA))throw Error('LOCAL_PROFILE_REQUIRED');
  const standard=path.join(env.LOCALAPPDATA,'Codex','wechat-dialog-instances');
  if(env.CODEX_WECHAT_REGISTRY_DIR){
    if(!path.isAbsolute(env.CODEX_WECHAT_REGISTRY_DIR)||path.basename(env.CODEX_WECHAT_REGISTRY_DIR).toLowerCase()!=='wechat-dialog-instances')throw Error('INVALID_INSTANCE_REGISTRY');
    const registry=await fs.realpath(env.CODEX_WECHAT_REGISTRY_DIR).catch(error=>{if(error.code==='ENOENT')return env.CODEX_WECHAT_REGISTRY_DIR;throw error;});
    return {registry,data_root:path.dirname(registry)};
  }
  const candidates=[standard],packages=path.join(env.LOCALAPPDATA,'Packages');
  let entries=[];
  try{entries=await fs.readdir(packages,{withFileTypes:true});}catch(error){if(error.code!=='ENOENT')throw Error('INSTANCE_REGISTRY_UNREADABLE');}
  for(const entry of entries)if(entry.isDirectory()&&/^OpenAI\.Codex_[a-z0-9]+$/i.test(entry.name))candidates.push(path.join(packages,entry.name,'LocalCache','Local','Codex','wechat-dialog-instances'));
  const registered=new Map();
  for(const candidate of candidates){
    try{
      const real=await fs.realpath(candidate),files=await fs.readdir(real,{withFileTypes:true});
      if(files.some(file=>file.isFile()&&registration.test(file.name)))registered.set(process.platform==='win32'?real.toLowerCase():real,real);
    }catch(error){if(error.code!=='ENOENT'&&error.code!=='ENOTDIR')throw Error('INSTANCE_REGISTRY_UNREADABLE');}
  }
  if(registered.size>1)throw Error('INSTANCE_REGISTRY_AMBIGUOUS');
  const registry=registered.size?[...registered.values()][0]:standard;
  return {registry,data_root:path.dirname(registry)};
}

export function instanceDataDirectory(name,directory,locations,env=process.env){
  const original=path.join(env.LOCALAPPDATA,'Codex',...(name==='primary'?['wechat-dialog']:['wechat-dialog-instances',name]));
  const normalize=value=>{const normalized=path.resolve(value);return process.platform==='win32'?normalized.toLowerCase():normalized;};
  if(normalize(directory)!==normalize(original))return directory;
  return path.join(locations.data_root,...(name==='primary'?['wechat-dialog']:['wechat-dialog-instances',name]));
}

if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  try{console.log(JSON.stringify({status:'instance_paths',...await instancePaths()}));}
  catch(error){console.log(JSON.stringify({status:'error',code:/^[A-Z_]+$/.test(error.message)?error.message:'INSTANCE_PATHS_FAILED'}));process.exitCode=1;}
}
