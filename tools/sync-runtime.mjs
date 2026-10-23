import fs from 'node:fs/promises';import path from 'node:path';import {fileURLToPath} from 'node:url';import {createHash} from 'node:crypto';
const app=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),project=path.dirname(app),manifest=[];
const hash=data=>createHash('sha256').update(data).digest('hex');
async function copy(source,target,{record=true}={}){await fs.mkdir(path.dirname(target),{recursive:true});const bytes=await fs.readFile(source);const existing=await fs.readFile(target).catch(error=>{if(error.code==='ENOENT')return null;throw error;});if(!existing?.equals(bytes))await fs.writeFile(target,bytes);if(record)manifest.push({path:path.relative(app,target).replaceAll('\\','/'),sha256:hash(bytes)});}
for(const name of ['wechat-dialog','wechat-notify']){
 const from=path.join(project,'skills',name),to=path.join(app,'runtime','skills',name);
 for(const entry of await fs.readdir(path.join(from,'scripts'),{withFileTypes:true})){if(entry.isFile()&&/\.(mjs|ps1)$/.test(entry.name))await copy(path.join(from,'scripts',entry.name),path.join(to,'scripts',entry.name));}
 for(const filename of ['package.json','package-lock.json']){try{await copy(path.join(from,filename),path.join(to,filename));}catch(error){if(error.code!=='ENOENT')throw error;}}
 await copy(path.join(app,'templates','skills',name+'.md'),path.join(to,'SKILL.md'));
 // Route is deliberately portable. Absence of notification-route.json selects the local Windows primary.
 if(name==='wechat-notify'){try{await fs.unlink(path.join(to,'notification-route.json'));}catch(error){if(error.code!=='ENOENT')throw error;}}
}
async function tree(from,to){for(const entry of await fs.readdir(from,{withFileTypes:true})){if(entry.name==='node_modules')continue;const source=path.join(from,entry.name),target=path.join(to,entry.name);if(entry.isDirectory())await tree(source,target);else if(entry.isFile())await copy(source,target);}}
// These are reviewed public defaults. Never ingest a live workspace's newly
// generated/private persona media while synchronizing service source.
const persona=path.join(app,'templates','workspace','outputs','persona');
await tree(persona,persona);
// Public docs are maintained in this software repository. Do not overwrite them
// with private parent-workspace histories or deployment evidence.
for(const file of ['FEATURES.md','OPERATIONS.md']){const target=path.join(app,'docs',file);manifest.push({path:path.relative(app,target).replaceAll('\\','/'),sha256:hash(await fs.readFile(target))});}
for(const file of ['access-policy.test.mjs','model-policy.test.mjs','persona-conversation.test.mjs','execution-policy.test.mjs']){
 const source=await fs.readFile(path.join(project,'tests',file),'utf8');const text=(/import os from 'node:os'/.test(source)?'':"import os from 'node:os';\n")+source.replaceAll('../skills/','../runtime/skills/').replaceAll("path.resolve('work',","path.join(os.tmpdir(),");
 const target=path.join(app,'tests',file);await fs.writeFile(target,text);manifest.push({path:path.relative(app,target).replaceAll('\\','/'),sha256:hash(text)});
}
const {version}=JSON.parse(await fs.readFile(path.join(app,'package.json'),'utf8'));
await fs.writeFile(path.join(app,'runtime-manifest.json'),JSON.stringify({version,files:manifest.sort((a,b)=>a.path.localeCompare(b.path))},null,2)+'\n');
console.log(JSON.stringify({status:'synced',files:manifest.length}));
