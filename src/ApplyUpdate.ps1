#requires -Version 5.1
param([string]$JobFile,[switch]$SelfTest,[switch]$NonInteractive)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$restoreAttempted=$false
$blockers=@()
function Stop-IfCancelled {if([IO.File]::Exists($JobFile+'.cancel')){exit 0}}
function Test-OriginalManager($job){
 try{$process=[Diagnostics.Process]::GetProcessById([int]$job.manager_pid)}catch{return $false}
 try{return (-not $job.manager_start_ticks -or $process.StartTime.ToUniversalTime().Ticks.ToString() -eq $job.manager_start_ticks)}finally{$process.Dispose()}
}
function Wait-InstallDirectory($job){
 if(-not $job.guard -or -not [IO.File]::Exists($job.guard)){throw 'UPDATE_PROCESS_UNVERIFIED'}
 $deadline=[datetime]::UtcNow.AddSeconds(30)
 do{
  Stop-IfCancelled
  $report=& $job.guard $job.app_root --report
  $code=$LASTEXITCODE
  if($code -eq 0){return}
  if($code -ne 42){throw 'UPDATE_PROCESS_UNVERIFIED'}
  try{$script:blockers=@(($report|ConvertFrom-Json).processes)}catch{throw 'UPDATE_PROCESS_UNVERIFIED'}
  if([datetime]::UtcNow -ge $deadline){throw 'UPDATE_FILES_IN_USE'}
  Start-Sleep -Milliseconds 400
 }while($true)
}
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
 if(-not [IO.File]::Exists($manager) -and $job.manager_root){$manager=Join-Path $job.manager_root 'ClawBot实例管理器.exe'}
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
 Stop-IfCancelled
 $job=[IO.File]::ReadAllText($JobFile,[Text.Encoding]::UTF8)|ConvertFrom-Json
 Assert-UpdateFile $job
 if($SelfTest){[Console]::WriteLine('UPDATE_HANDOFF_VALIDATED');exit 0}
 Stop-IfCancelled
 [IO.File]::WriteAllText($JobFile+'.ready','ready')
 $deadline=[datetime]::UtcNow.AddSeconds(45)
 while(Test-OriginalManager $job){Stop-IfCancelled;if([datetime]::UtcNow -ge $deadline){throw 'UPDATE_MANAGER_STILL_RUNNING'};Start-Sleep -Milliseconds 200}
 Wait-InstallDirectory $job
 Assert-UpdateFile $job
 Stop-IfCancelled
 $arguments=@('/SP-','/NORESTART','/SUPPRESSMSGBOXES',('/DIR="'+$job.app_root+'"'),('/LOG="'+$JobFile+'.install.log"'))
 $arguments+=if($NonInteractive){'/VERYSILENT'}else{'/SILENT'}
 $install=Start-Process -FilePath $job.installer -ArgumentList $arguments -WorkingDirectory ([IO.Path]::GetDirectoryName($job.installer)) -WindowStyle Normal -PassThru
 $install.WaitForExit()
 $resumeFailed=@(Restore-UpdateServices $job);$restoreAttempted=$true
 [IO.File]::WriteAllText($JobFile+'.result.json',(@{status='installer_exited';exit_code=$install.ExitCode;resume_failed=$resumeFailed}|ConvertTo-Json -Compress))
 Open-UpdatedManager $job
 if($install.ExitCode -ne 0){throw 'UPDATE_INSTALLER_NOT_COMPLETED'}
 if($resumeFailed.Count){throw 'UPDATE_SERVICE_RESTART_FAILED'}
}catch{
 $safe=if($_.Exception.Message -match '^UPDATE_[A-Z_]+$'){$_.Exception.Message}else{'UPDATE_HANDOFF_FAILED'}
 if($JobFile){[IO.File]::WriteAllText($JobFile+'.error.json',(@{status='error';code=$safe;processes=@($blockers)}|ConvertTo-Json -Depth 5 -Compress))}
 if($SelfTest){[Console]::WriteLine($safe);[Console]::Error.WriteLine($_.Exception.Message);exit 1}
 if($job -and -not $restoreAttempted -and -not (Test-OriginalManager $job)){try{[void]@(Restore-UpdateServices $job);Open-UpdatedManager $job}catch{}}
 if($NonInteractive){[Console]::WriteLine($safe);exit 1}
 Add-Type -AssemblyName PresentationFramework
 $details=if($safe -eq 'UPDATE_FILES_IN_USE'){'仍在使用安装目录的进程：'+(($blockers|ForEach-Object {$_.name+' (PID '+$_.pid+')'}) -join '、')+'。请等待其退出后重试。'}else{''}
 [void][Windows.MessageBox]::Show('更新未完成（'+$safe+'）。'+$details+'原账号数据会保留；请重新打开管理器核对服务，必要时重试安装。','ClawBot实例管理器')
}
