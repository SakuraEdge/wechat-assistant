#requires -Version 5.1
[CmdletBinding()]param([switch]$NoLaunch)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'src\Runtime.ps1')
$node=Resolve-ManagerNode $PSScriptRoot
$version=& $node --version
if($version -notmatch '^v(\d+)\.' -or [int]$Matches[1] -lt 24){throw 'Node.js 24+ is required'}
$skill=Join-Path $PSScriptRoot 'runtime\skills\wechat-dialog'
if(-not(Test-Path -LiteralPath (Join-Path $skill 'node_modules\qrcode'))){
 $npm=Join-Path (Split-Path $node -Parent) 'npm.cmd'
 Push-Location $skill
 try{& $npm ci --omit=dev --no-audit --no-fund;if($LASTEXITCODE -ne 0){throw 'npm ci failed'}}finally{Pop-Location}
}
if(-not $env:CODEX_APP_TOOLS_PIPE_PATH -or -not $env:CODEX_CLI_PATH){throw 'Run initialization from the current Codex desktop tool environment. Use the manager connection guide.'}
# status refreshes the encrypted, whitelisted desktop connection from Codex.
& $node (Join-Path $skill 'scripts\wechat-bot.mjs') status
if($LASTEXITCODE -ne 0){throw 'Desktop connection initialization failed'}
& $node (Join-Path $PSScriptRoot 'tools\install-skills.mjs')
if($LASTEXITCODE -ne 0){throw 'Skill entry installation failed'}
if(-not(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'ClawBot实例管理器.exe'))){& (Join-Path $PSScriptRoot 'build.ps1')}
if(-not $NoLaunch){Start-Process -FilePath (Join-Path $PSScriptRoot 'ClawBot实例管理器.exe') -WindowStyle Normal}
