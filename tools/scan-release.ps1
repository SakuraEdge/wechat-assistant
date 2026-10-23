#requires -Version 5.1
[CmdletBinding()]param([Parameter(Mandatory=$true)][string]$Directory,[Parameter(Mandatory=$true)][string]$ReportFile)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($Directory)
$platform=Join-Path $env:ProgramData 'Microsoft\Windows Defender\Platform'
$scanner=@(Get-ChildItem -LiteralPath $platform -Directory -ErrorAction SilentlyContinue|Where-Object {$_.Name -match '^\d+\.\d+\.\d+\.\d+-\d+$'}|Sort-Object {[version]($_.Name -replace '-\d+$','')} -Descending|ForEach-Object {Join-Path $_.FullName 'MpCmdRun.exe'}|Where-Object {[IO.File]::Exists($_)}|Select-Object -First 1)
if(-not $scanner.Count){throw 'RELEASE_DEFENDER_UNAVAILABLE'}
$status=Get-MpComputerStatus
if(-not $status.AMServiceEnabled -or -not $status.AntivirusEnabled -or -not $status.RealTimeProtectionEnabled){throw 'RELEASE_DEFENDER_INACTIVE'}
$files=@(Get-ChildItem -LiteralPath $root -File|Where-Object {$_.Extension -in @('.exe','.zip')})
if(-not $files.Count){throw 'RELEASE_SCAN_INPUT_EMPTY'}
$reports=@();$failed=$false
foreach($file in $files){
 $stream=[IO.File]::OpenRead($file.FullName);$hash=[Security.Cryptography.SHA256]::Create()
 try{$digest=([BitConverter]::ToString($hash.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$stream.Dispose();$hash.Dispose()}
 # This option affects this diagnostic scan only: it scans archives/exclusions and reports without remediation.
 # No Defender setting, allowance or exclusion is changed.
 $output=& $scanner[0] -Scan -ScanType 3 -File $file.FullName -DisableRemediation 2>&1
 $code=$LASTEXITCODE
 $reports+=@{name=$file.Name;bytes=$file.Length;sha256=$digest;exit_code=$code;result=$(if($code -eq 0){'no_threats_reported'}else{'detection_or_scan_error'})}
 if($code -ne 0){$failed=$true}
}
$report=@{schema=1;scanned_at=[datetime]::UtcNow.ToString('o');scanner='Microsoft Defender Antivirus';signature_version=$status.AntivirusSignatureVersion;engine_version=$status.AMEngineVersion;realtime_enabled=[bool]$status.RealTimeProtectionEnabled;files=$reports;result=$(if($failed){'blocked'}else{'no_threats_reported'});limitation='Local scan only; not a vendor verdict or a guarantee for other computers.'}
[IO.File]::WriteAllText($ReportFile,($report|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
if($failed){throw 'RELEASE_SECURITY_SCAN_BLOCKED'}
[Console]::WriteLine('RELEASE_DEFENDER_SCAN_OK')
