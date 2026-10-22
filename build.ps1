#requires -Version 5.1
[CmdletBinding()]param()
$ErrorActionPreference='Stop'
$compiler=Join-Path ([Environment]::GetFolderPath('Windows')) 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if(-not(Test-Path -LiteralPath $compiler)){$compiler=Join-Path ([Environment]::GetFolderPath('Windows')) 'Microsoft.NET\Framework\v4.0.30319\csc.exe'}
if(-not(Test-Path -LiteralPath $compiler)){throw '.NET Framework C# compiler not found'}
$automation=[System.Management.Automation.PowerShell].Assembly.Location
& $compiler /nologo /target:winexe /reference:System.Windows.Forms.dll ('/reference:'+$automation) ('/out:'+(Join-Path $PSScriptRoot '微信助手.exe')) (Join-Path $PSScriptRoot 'src\Launcher.cs')
if($LASTEXITCODE -ne 0){throw 'Launcher build failed'}
Write-Output 'Build complete: 微信助手.exe'
