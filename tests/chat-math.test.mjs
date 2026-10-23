import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs/promises';import path from 'node:path';import {fileURLToPath} from 'node:url';import {createHash} from 'node:crypto';import {spawn} from 'node:child_process';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
test('offline formula libraries and licenses exactly match pinned dependency hashes',async()=>{
 const directory=path.join(root,'assets/math'),pins=JSON.parse(await fs.readFile(path.join(directory,'dependencies.json'),'utf8'));
 assert.equal(pins.packages.length,2);assert.ok(pins.packages.every(x=>x.version==='2.1.0'&&x.framework==='net462'&&x.url.startsWith('https://api.nuget.org/v3-flatcontainer/')));
 assert.deepEqual(pins.files.map(x=>x.path).sort(),['FONT-LICENSES.md','LICENSE-XAML-Math.md','WpfMath.dll','XamlMath.Shared.dll'].sort());
 for(const item of pins.files){const data=await fs.readFile(path.join(directory,item.path));assert.equal(data.length,item.bytes);assert.equal(createHash('sha256').update(data).digest('hex'),item.sha256);}
});
test('Windows chat renders native formulas while preserving code, money, original text and unsupported input',{skip:process.platform!=='win32'},async()=>{
 const result=await new Promise((resolve,reject)=>{const p=spawn('powershell.exe',['-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',path.join(root,'tests/ChatMath.Check.ps1'),'-AppRoot',root],{windowsHide:true,stdio:['ignore','pipe','pipe']});let output='';p.stdout.on('data',x=>output+=x);p.stderr.on('data',x=>output+=x);p.on('error',reject);p.on('exit',code=>resolve({code,output}));});
 assert.equal(result.code,0,result.output);assert.match(result.output,/CHAT_MATH_OK/);
});
