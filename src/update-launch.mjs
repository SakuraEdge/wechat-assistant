import path from 'node:path';import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
export function launchUpdateHelper(script,job,directory,{nonInteractive=false}={}){
 const executable=path.join(process.env.SystemRoot||process.env.WINDIR,'System32','WindowsPowerShell','v1.0','powershell.exe');
 // Direct DETACHED_PROCESS can exit before -File; an attached console dies with its parent.
 // Start-Process creates an independent hidden helper. The controller still waits for readiness.
 const starter=fileURLToPath(new URL('./StartUpdate.ps1',import.meta.url));
 return spawn(executable,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',starter,'-ScriptFile',script,'-JobFile',job,'-WorkingDirectory',directory,...(nonInteractive?['-NonInteractive']:[])],{cwd:directory,windowsHide:true,stdio:'ignore'});
}
