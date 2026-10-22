#requires -Version 5.1
param([string]$JobFile,[switch]$SelfTest,[switch]$NonInteractive)
$ErrorActionPreference='Stop'
$restoreAttempted=$false
function Restore-UpdateServices($job){
 foreach($name in @($job.resume_instances)){
  if($name -notmatch '^[a-z][a-z0-9-]{0,47}$'){continue}
  try{
   $request=Join-Path $job.jobs_directory (([guid]::NewGuid().ToString('N'))+'.json')
   [IO.File]::WriteAllText($request,(@{action='start';name=$name}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
   & (Join-Path $job.app_root 'runtime\node\node.exe') (Join-Path $job.app_root 'src\controller.mjs') --request $request | Out-Null
   if($LASTEXITCODE -ne 0){$name}
  }catch{$name}
 }
}
function Open-UpdatedManager($job){
 Add-Type -AssemblyName System.Management
 $manager=Join-Path $job.app_root 'ClawBot实例管理器.exe'
 $search=[Management.ManagementObjectSearcher]::new("SELECT ExecutablePath FROM Win32_Process WHERE Name='ClawBot实例管理器.exe'")
 try{$already=@($search.Get()|Where-Object {$_.ExecutablePath -ieq $manager}).Count}finally{$search.Dispose()}
 if(-not $already){Start-Process -FilePath $manager -WindowStyle Normal}
}
function Assert-UpdateFile($job){
 $root=[IO.Path]::GetFullPath($job.download_root).TrimEnd('\')+'\'
 $file=[IO.Path]::GetFullPath($job.installer)
 if(-not $file.StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -or $job.sha256 -notmatch '^[a-f0-9]{64}$'){throw 'UPDATE_PATH_REJECTED'}
 $item=Get-Item -LiteralPath $file
 $cursor=$item
 while($cursor -and $cursor.FullName.Length -ge $root.TrimEnd('\').Length){if($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'UPDATE_PATH_REJECTED'};$cursor=if($cursor.PSIsContainer){$cursor.Parent}else{$cursor.Directory}}
 $stream=[IO.File]::OpenRead($file);$algorithm=[Security.Cryptography.SHA256]::Create()
 try{$hash=([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$stream.Dispose();$algorithm.Dispose()}
 if($item.Length -ne $job.bytes -or $hash -ine $job.sha256){throw 'UPDATE_HASH_MISMATCH'}
}
try{
 $job=[IO.File]::ReadAllText($JobFile,[Text.Encoding]::UTF8)|ConvertFrom-Json
 Assert-UpdateFile $job
 if($SelfTest){[Console]::WriteLine('UPDATE_HANDOFF_VALIDATED');exit 0}
 [IO.File]::WriteAllText($JobFile+'.ready','ready')
 $deadline=[datetime]::UtcNow.AddSeconds(45)
 while(Get-Process -Id $job.manager_pid -ErrorAction SilentlyContinue){if([datetime]::UtcNow -ge $deadline){throw 'UPDATE_MANAGER_STILL_RUNNING'};Start-Sleep -Milliseconds 200}
 Assert-UpdateFile $job
 $install=Start-Process -FilePath $job.installer -ArgumentList @('/SP-','/NORESTART',('/DIR="'+$job.app_root+'"')) -WorkingDirectory ([IO.Path]::GetDirectoryName($job.installer)) -WindowStyle Normal -PassThru
 $install.WaitForExit()
 $resumeFailed=@(Restore-UpdateServices $job);$restoreAttempted=$true
 [IO.File]::WriteAllText($JobFile+'.result.json',(@{status='installer_exited';exit_code=$install.ExitCode;resume_failed=$resumeFailed}|ConvertTo-Json -Compress))
 Open-UpdatedManager $job
 if($install.ExitCode -ne 0){throw 'UPDATE_INSTALLER_NOT_COMPLETED'}
 if($resumeFailed.Count){throw 'UPDATE_SERVICE_RESTART_FAILED'}
}catch{
 $safe=if($_.Exception.Message -match '^UPDATE_[A-Z_]+$'){$_.Exception.Message}else{'UPDATE_HANDOFF_FAILED'}
 if($JobFile){[IO.File]::WriteAllText($JobFile+'.error.json',(@{status='error';code=$safe}|ConvertTo-Json -Compress))}
 if($SelfTest){[Console]::WriteLine($safe);[Console]::Error.WriteLine($_.Exception.Message);exit 1}
 if($job -and -not $restoreAttempted -and -not (Get-Process -Id $job.manager_pid -ErrorAction SilentlyContinue)){try{[void]@(Restore-UpdateServices $job);Open-UpdatedManager $job}catch{}}
 if($NonInteractive){[Console]::WriteLine($safe);exit 1}
 Add-Type -AssemblyName PresentationFramework
 [void][Windows.MessageBox]::Show('更新未完成（'+$safe+'）。原账号数据会保留；请重新打开管理器核对服务，必要时重试安装。','ClawBot实例管理器')
}
