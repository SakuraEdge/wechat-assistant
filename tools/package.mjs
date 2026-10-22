import fs from 'node:fs/promises';import path from 'node:path';import os from 'node:os';import {fileURLToPath} from 'node:url';import {spawnSync} from 'node:child_process';import {createHash} from 'node:crypto';
const app=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),stage=await fs.mkdtemp(path.join(os.tmpdir(),'wechat-manager-release-'));
const target=path.join(stage,'WeChatAssistant');await fs.mkdir(target);const records=[];
async function copy(source,destination){const value=await fs.readFile(source);await fs.mkdir(path.dirname(destination),{recursive:true});await fs.writeFile(destination,value);records.push({path:path.relative(target,destination).replaceAll('\\','/'),sha256:createHash('sha256').update(value).digest('hex')});}
async function tree(dir,destination){for(const entry of await fs.readdir(dir,{withFileTypes:true})){if(entry.isSymbolicLink())throw Error('PACKAGE_LINK_FORBIDDEN');const file=path.join(dir,entry.name),out=path.join(destination,entry.name);if(entry.isDirectory())await tree(file,out);else if(entry.isFile())await copy(file,out);}}
for(const name of ['src','runtime','templates','docs','tests','tools'])await tree(path.join(app,name),path.join(target,name));
for(const name of ['README.md','AGENTS.md','package.json','.gitignore','.gitattributes','runtime-manifest.json','build.ps1','initialize.ps1','打开微信助手.vbs','微信助手.exe'])await copy(path.join(app,name),path.join(target,name));
for(const item of records)if(/\.dpapi$|\.log$|token\.xml$|notification-route\.json$|runtime-config\.json$|wechat-clawbot-login\.png$|(?:^|\/)(?:jobs|qr|instances)(?:\/|$)/i.test(item.path))throw Error('PRIVATE_FILE_IN_PACKAGE');
await fs.writeFile(path.join(target,'release-manifest.json'),JSON.stringify({version:'1.0.0',files:records},null,2)+'\n');
await fs.mkdir(path.join(app,'dist'),{recursive:true});const output=path.join(app,'dist','WeChat-Assistant-Manager-Windows-v1.0.0.zip');
if(await fs.stat(output).then(()=>true,()=>false))throw Error('PACKAGE_ALREADY_EXISTS');
const command='Compress-Archive -LiteralPath $env:WX_MANAGER_STAGE -DestinationPath $env:WX_MANAGER_PACKAGE -CompressionLevel Optimal';
const result=spawnSync('powershell.exe',['-NoProfile','-Command',command],{env:{...process.env,WX_MANAGER_STAGE:target,WX_MANAGER_PACKAGE:output},windowsHide:true,encoding:'utf8'});if(result.status!==0)throw Error('PACKAGE_COMPRESSION_FAILED');
console.log(JSON.stringify({status:'packaged',path:output,files:records.length,bytes:(await fs.stat(output)).size,sha256:createHash('sha256').update(await fs.readFile(output)).digest('hex')}));
