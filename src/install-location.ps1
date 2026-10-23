#requires -Version 5.1
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
try{
 $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Uninstall\{F3D40C68-3D70-4972-95E5-2E4F902F0C6A}_is1')
 $registered=$null
 if($key){try{$registered=$key.GetValue('InstallLocation')}finally{$key.Dispose()}}
 $directory=if($registered -and [IO.Path]::IsPathRooted($registered)){$registered}else{Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\ClawBotInstanceManager'}
 [Console]::WriteLine((@{status='install_location';directory=$directory}|ConvertTo-Json -Compress))
}catch{[Console]::WriteLine('{"status":"error","code":"UPDATE_INSTALL_LOCATION_FAILED"}');exit 1}
