#requires -Version 5.1
[CmdletBinding()]param([switch]$NoLaunch)
$ErrorActionPreference='Stop'
$node=if(Test-Path -LiteralPath 'C:\Program Files\nodejs\node.exe'){'C:\Program Files\nodejs\node.exe'}else{(Get-Command node.exe -ErrorAction Stop).Source}
$version=& $node --version
if($version -notmatch '^v(\d+)\.' -or [int]$Matches[1] -lt 24){throw 'Node.js 24+ is required'}
$skill=Join-Path $PSScriptRoot 'runtime\skills\wechat-dialog'
if(-not(Test-Path -LiteralPath (Join-Path $skill 'node_modules\qrcode'))){
 $npm=Join-Path (Split-Path $node -Parent) 'npm.cmd'
 Push-Location $skill
 try{& $npm ci --omit=dev --no-audit --no-fund;if($LASTEXITCODE -ne 0){throw 'npm ci failed'}}finally{Pop-Location}
}
# status also refreshes the encrypted, whitelisted desktop connection when called from Codex.
& $node (Join-Path $skill 'scripts\wechat-bot.mjs') status
if($LASTEXITCODE -ne 0){throw 'Desktop connection initialization failed'}
& $node (Join-Path $PSScriptRoot 'tools\install-skills.mjs')
if($LASTEXITCODE -ne 0){throw 'Skill entry installation failed'}
if(-not(Test-Path -LiteralPath (Join-Path $PSScriptRoot '微信助手.exe'))){& (Join-Path $PSScriptRoot 'build.ps1')}
if(-not $NoLaunch){Start-Process -FilePath (Join-Path $PSScriptRoot '微信助手.exe') -WindowStyle Normal}
