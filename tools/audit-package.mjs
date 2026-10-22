import fs from 'node:fs/promises';import path from 'node:path';import {fileURLToPath} from 'node:url';import {createHash} from 'node:crypto';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');const errors=[],files=[];
async function walk(dir){for(const entry of await fs.readdir(dir,{withFileTypes:true})){if(['node_modules','.git','dist'].includes(entry.name))continue;const file=path.join(dir,entry.name);if(entry.isSymbolicLink()){errors.push('SYMLINK:'+path.relative(root,file));continue;}if(entry.isDirectory())await walk(file);else files.push(file);}}
await walk(root);
for(const file of files){const relative=path.relative(root,file).replaceAll('\\','/');
 if(/(?:^|\/)(?:state|token|auth|credentials|desktop-connection)\.(?:dpapi|json|xml)|\.dpapi$|\.log$|wechat-clawbot-login\.png|(?:^|\/)(?:work|jobs|qr|instances)(?:\/|$)/i.test(relative))errors.push('PRIVATE_PATH:'+relative);
 if(/\.(?:mjs|ps1|md|json|cs|gitignore|vbs)$/.test(file)){const text=await fs.readFile(file,'utf8');if(/(?:sk-[a-zA-Z0-9_-]{20,}|Bearer\s+[A-Za-z0-9_-]{24,}|[A-Z]:[\\/]Users[\\/][^%<][^\\/\s"']*)/.test(text))errors.push('HOST_OR_SECRET_LITERAL:'+relative);}
}
const manifest=JSON.parse(await fs.readFile(path.join(root,'runtime-manifest.json'),'utf8'));
for(const item of manifest.files){const resolved=path.resolve(root,item.path);if(!resolved.startsWith(root+path.sep)){errors.push('MANIFEST_PATH');continue;}try{const actual=createHash('sha256').update(await fs.readFile(resolved)).digest('hex');if(actual!==item.sha256)errors.push('HASH_MISMATCH:'+item.path);}catch{errors.push('MISSING:'+item.path);}}
console.log(JSON.stringify({status:errors.length?'failed':'passed',files:files.length,manifest_files:manifest.files.length,errors},null,2));if(errors.length)process.exitCode=1;
