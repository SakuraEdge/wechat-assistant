import fs from 'node:fs/promises';import path from 'node:path';import {randomBytes} from 'node:crypto';
export const DEFAULT_MODEL=Object.freeze({model:'gpt-6.1-sol',effort:'high'});
export const MODEL_POLICY_VERSION='wechat-model-selection-v1';
export function normalizeCatalog(items){
 const seen=new Set();return items.filter(item=>!item.hidden&&typeof item.model==='string'&&!seen.has(item.model)&&seen.add(item.model)).map(item=>({model:item.model,id:item.id||item.model,display_name:item.displayName||item.model,description:item.description||'',default_effort:item.defaultReasoningEffort??null,efforts:(item.supportedReasoningEfforts||[]).filter(value=>typeof value.reasoningEffort==='string').map(value=>({value:value.reasoningEffort,description:value.description||value.reasoningEffort}))}));
}
export function validateSelection(selection,catalog){
 const model=catalog.find(item=>item.model===selection.model);if(!model)throw Error('MODEL_NOT_AVAILABLE');
 const effort=selection.effort??null;if(model.efforts.length?!model.efforts.some(item=>item.value===effort):effort!==null)throw Error('EFFORT_NOT_AVAILABLE');
 return {model:model.model,effort};
}
export const modelFor=state=>state?.modelSelection||DEFAULT_MODEL;
export async function loadModelPolicy(directory){
 let value;try{value=JSON.parse(await fs.readFile(path.join(directory,'model-policy.json'),'utf8'));}catch(error){if(error.code==='ENOENT')return {...DEFAULT_MODEL};throw Error('MODEL_POLICY_INVALID');}
 if(typeof value.model!=='string'||!value.model||value.model.length>160||/[\r\n\0]/.test(value.model)||value.effort!==null&&(typeof value.effort!=='string'||!/^[a-z][a-z0-9_-]{0,39}$/.test(value.effort)))throw Error('MODEL_POLICY_INVALID');
 return {model:value.model,effort:value.effort};
}
export async function saveModelPolicy(directory,selection,catalog){const valid=validateSelection(selection,catalog);await fs.mkdir(directory,{recursive:true});const filename=path.join(directory,'model-policy.json'),temp=filename+'.'+randomBytes(6).toString('hex')+'.tmp';await fs.writeFile(temp,JSON.stringify({...valid,source:'codex-model-list',validated_at:new Date().toISOString()},null,2)+'\n',{flag:'wx'});await fs.rename(temp,filename);return valid;}
