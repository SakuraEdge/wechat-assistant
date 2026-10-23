#requires -Version 5.1
param([string]$ScriptFile,[string]$JobFile,[string]$WorkingDirectory,[switch]$NonInteractive)
$ErrorActionPreference='Stop'
try{
 $executable=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $arguments=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',('"'+$ScriptFile+'"'),'-JobFile',('"'+$JobFile+'"'))
 if($NonInteractive){$arguments+='-NonInteractive'}
 # Start-Process gives the helper its own hidden console and an independent lifetime.
 $child=Start-Process -FilePath $executable -ArgumentList $arguments -WorkingDirectory $WorkingDirectory -WindowStyle Hidden -PassThru
 [IO.File]::WriteAllText($JobFile+'.launch.json',(@{pid=$child.Id}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
}catch{
 [IO.File]::WriteAllText($JobFile+'.error.json','{"status":"error","code":"UPDATE_HELPER_START_FAILED"}',[Text.UTF8Encoding]::new($false))
 exit 1
}
