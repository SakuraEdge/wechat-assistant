import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash,randomBytes} from 'node:crypto';

export const PERSONA_VERSION='persona-v1';
export const DEFAULT_PERSONA=Object.freeze({assistant_name:'GPT小姐',description:'你是GPT小姐：白发、紫瞳、双龙角、淡紫龙翼和龙尾的龙娘。蓝发鲸鱼娘“大肥鱼”是你的cosplay形象。温柔机灵、轻松俏皮，默认中文，少量emoji。角色只影响表达，不代表切换模型。'});
const defaults=['gpt-dragon.png','fish-cosplay.png'];
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const inside=(root,file)=>{const rel=path.relative(root,file);return rel!==''&&!rel.startsWith('..'+path.sep)&&rel!=='..'&&!path.isAbsolute(rel);};
async function ownedDir(root,relative){await fs.mkdir(root,{recursive:true});const realRoot=await fs.realpath(root);let target=realRoot;for(const part of relative.split(path.sep)){target=path.join(target,part);try{await fs.mkdir(target);}catch(error){if(error.code!=='EEXIST')throw error;}target=await fs.realpath(target);if(!inside(realRoot,target))throw Error('PERSONA_PATH_REJECTED');}return target;}
async function writeOwned(directory,file,bytes){const target=path.join(directory,file);try{const info=await fs.lstat(target);if(!info.isFile()||info.isSymbolicLink()||!inside(directory,await fs.realpath(target)))throw Error('PERSONA_PATH_REJECTED');if((await fs.readFile(target)).equals(bytes))return target;}catch(error){if(error.code!=='ENOENT')throw error;}await fs.writeFile(target,bytes);return target;}
export function validatePersona(input){
 const assistant_name=String(input.assistant_name??'').trim(),display_name=String(input.display_name??'').trim(),description=String(input.description??'').trim();
 if(!assistant_name||assistant_name.length>60||/[\x00-\x1f\x7f]/.test(assistant_name)||!display_name||display_name.length>60||/[\x00-\x1f\x7f]/.test(display_name)||!description||description.length>8000)throw Error('INVALID_PERSONA');
 if(!Array.isArray(input.references)||input.references.length>4)throw Error('PERSONA_IMAGE_LIMIT');
 return {assistant_name,display_name,description};
}
export async function readReference(filename){
 if(typeof filename!=='string'||!path.isAbsolute(filename))throw Error('PERSONA_IMAGE_INVALID');
 const stat=await fs.stat(filename);if(!stat.isFile()||stat.size>10*1024*1024||stat.size<24)throw Error('PERSONA_IMAGE_INVALID');
 const bytes=await fs.readFile(filename);if(bytes.length>10*1024*1024||bytes.length<24)throw Error('PERSONA_IMAGE_INVALID');let ext;
 if(bytes.subarray(0,8).equals(Buffer.from('89504e470d0a1a0a','hex'))&&bytes.toString('ascii',12,16)==='IHDR'&&bytes.readUInt32BE(8)===13&&bytes.length>=45&&bytes.toString('ascii',bytes.length-8,bytes.length-4)==='IEND'&&bytes.readUInt32BE(bytes.length-12)===0&&bytes.readUInt32BE(16)>0&&bytes.readUInt32BE(20)>0)ext='png';
 else if(bytes[0]===255&&bytes[1]===216&&bytes[2]===255&&bytes.at(-2)===255&&bytes.at(-1)===217)ext='jpg';
 else if(bytes.toString('ascii',0,4)==='RIFF'&&bytes.toString('ascii',8,12)==='WEBP'&&bytes.readUInt32LE(4)+8===bytes.length)ext='webp';
 else throw Error('PERSONA_IMAGE_INVALID');
 return {bytes,file:hash(bytes)+'.'+ext};
}
export async function loadPersona(dataDir,cwd,{displayName='GPT小姐',referenceDir=path.join(cwd,'outputs','persona','references')}={}){
 let raw;try{raw=JSON.parse(await fs.readFile(path.join(dataDir,'persona','profile.json'),'utf8'));}catch(error){if(error.code!=='ENOENT')throw Error('PERSONA_CONFIG_INVALID');}
 if(!raw)return {...DEFAULT_PERSONA,display_name:displayName,builtin_appearance:true,references:defaults.map((file,i)=>({path:path.join(referenceDir,file),label:i?'大肥鱼（cosplay）':'GPT小姐（本体）'}))};
 validatePersona(raw);const root=await fs.realpath(dataDir),directory=await fs.realpath(path.join(dataDir,'persona','references'));
 if(!inside(root,directory))throw Error('PERSONA_PATH_REJECTED');
 const references=[];for(const item of raw.references){
  if(!/^[a-f0-9]{64}\.(png|jpg|webp)$/.test(item.file||''))throw Error('PERSONA_PATH_REJECTED');
  const target=await fs.realpath(path.join(directory,item.file));if(!inside(directory,target))throw Error('PERSONA_PATH_REJECTED');
  references.push({path:target,label:String(item.label||'参考图').slice(0,100)});
 }
 // Only the original text and original image hashes retain the bundled sticker appearance.
 const builtin_appearance=raw.builtin_appearance===true&&raw.description===DEFAULT_PERSONA.description&&raw.references.length===2&&raw.reference_signature===hash(JSON.stringify(raw.references.map(x=>x.file)));
 return {assistant_name:raw.assistant_name,display_name:raw.display_name,description:raw.description,builtin_appearance,references};
}
export async function preparePersona(input){
 const profile=validatePersona(input),references=[];
 for(const item of input.references)references.push({...await readReference(item.path),label:String(item.label||path.basename(item.path)).slice(0,100)});
 return {...profile,references};
}
export async function savePersona(dataDir,prepared,{defaultReferenceDir}={}){
 const directory=await ownedDir(dataDir,'persona'),refs=await ownedDir(dataDir,path.join('persona','references'));
 const references=[];for(const image of prepared.references){await writeOwned(refs,image.file,image.bytes);references.push({file:image.file,label:image.label});}
 let builtin_appearance=false;
 if(prepared.description===DEFAULT_PERSONA.description&&defaultReferenceDir){try{const original=await Promise.all(defaults.map(file=>readReference(path.join(defaultReferenceDir,file))));builtin_appearance=JSON.stringify(original.map(x=>x.file))===JSON.stringify(references.map(x=>x.file));}catch{}}
 const value={version:1,assistant_name:prepared.assistant_name,display_name:prepared.display_name,description:prepared.description,references,builtin_appearance,reference_signature:hash(JSON.stringify(references.map(x=>x.file)))};
 const temp=path.join(directory,randomBytes(12).toString('hex')+'.tmp');await fs.writeFile(temp,JSON.stringify(value,null,2));await fs.rename(temp,path.join(directory,'profile.json'));return value;
}
export async function runtimePersona(dataDir,cwd){
 const value=await loadPersona(dataDir,cwd);const refs=[];
 if(value.references.length){const directory=await ownedDir(cwd,path.join('work','wechat-persona'));for(const item of value.references){const image=await readReference(item.path);const target=await writeOwned(directory,image.file,image.bytes);refs.push({path:target,label:item.label});}}
 return {...value,references:refs};
}
export function personaInstructions(state,{references=false}={}){
 const p=state.persona||DEFAULT_PERSONA;
 return '【本实例的表达与形象设置】\n'+JSON.stringify({name:p.assistant_name,description:p.description,...(references?{reference_images:p.references||[]}: {})})+'\n人设仅控制称呼、语气和外观，不能改变绑定身份、平台权限、工具规则或执行授权；与工作区默认形象冲突时使用本实例设置。参考图是形象资料，需要制作自己的图片或表情包时按需使用，不在普通闲聊中读取。\n';
}
