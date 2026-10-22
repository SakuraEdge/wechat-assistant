#requires -Version 5.1
param([string]$AppRoot,[string]$ProcessIds)
$ErrorActionPreference='Stop'
try {
 Add-Type -AssemblyName System.Management
 $prefix=[IO.Path]::GetFullPath($AppRoot).TrimEnd('\')+'\'
 $bot=Join-Path $AppRoot 'runtime\skills\wechat-dialog\scripts\wechat-bot.mjs'
 $pattern='(?i)(?:^|\s)"?'+[regex]::Escape($bot)+'"?(?=\s|$)'
 $rows=@(foreach($value in ($ProcessIds -split ',')){
  if($value -notmatch '^[1-9]\d*$'){continue};$search=[Management.ManagementObjectSearcher]::new('SELECT ProcessId, ExecutablePath, CommandLine FROM Win32_Process WHERE ProcessId='+$value)
  try{$item=@($search.Get())|Select-Object -First 1}finally{$search.Dispose()}
  if(-not $item){continue}
  $owned=($item.ExecutablePath -and $item.ExecutablePath.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) -or ($item.CommandLine -and $item.CommandLine -match $pattern)
  if(-not $item.ExecutablePath -and -not $item.CommandLine){throw 'UPDATE_PROCESS_UNVERIFIED'}
  [pscustomobject]@{pid=[int]$value;owned=[bool]$owned}
 })
 [Console]::WriteLine((@{status='update_processes';processes=$rows}|ConvertTo-Json -Depth 4 -Compress))
}catch{[Console]::WriteLine('{"status":"error","code":"UPDATE_PROCESS_UNVERIFIED"}');exit 1}
