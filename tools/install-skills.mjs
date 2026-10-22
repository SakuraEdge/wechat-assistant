import fs from 'node:fs/promises';import path from 'node:path';import {fileURLToPath,pathToFileURL} from 'node:url';
const app=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),home=process.env.CODEX_HOME||path.join(process.env.USERPROFILE,'.codex');const installed=[],kept=[];
for(const name of ['wechat-dialog','wechat-notify']){
 const source=path.join(app,'runtime','skills',name),target=path.join(home,'skills',name);
 try{await fs.access(path.join(target,'SKILL.md'));kept.push(name);continue;}catch(error){if(error.code!=='ENOENT')throw error;}
 await fs.mkdir(path.join(target,'scripts'),{recursive:true});await fs.copyFile(path.join(source,'SKILL.md'),path.join(target,'SKILL.md'));
 for(const file of await fs.readdir(path.join(source,'scripts'))){
  const actual=path.join(source,'scripts',file),entry=path.join(target,'scripts',file);
  if(file.endsWith('.ps1'))await fs.writeFile(entry,'\uFEFF& \''+actual.replaceAll("'","''")+'\' @args\nif ($null -ne $LASTEXITCODE) { exit $LASTEXITCODE }\n');
  else if(file.endsWith('.mjs'))await fs.writeFile(entry,'export * from '+JSON.stringify(pathToFileURL(actual).href)+';\n');
 }
 installed.push(name);
}
console.log(JSON.stringify({status:'skills_ready',installed,existing_preserved:kept}));
