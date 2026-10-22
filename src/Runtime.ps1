#requires -Version 5.1
function Resolve-ManagerNode([string]$Root) {
 $candidates=@((Join-Path $Root 'runtime\node\node.exe'),(Join-Path $env:ProgramFiles 'nodejs\node.exe'))
 $found=Get-Command node.exe -ErrorAction SilentlyContinue;if($found){$candidates+=@($found.Source)}
 foreach($candidate in $candidates){if(Test-Path -LiteralPath $candidate -PathType Leaf){$version=& $candidate --version;if($LASTEXITCODE -eq 0 -and $version -match '^v(\d+)\.' -and [int]$Matches[1] -ge 24){return $candidate}}}
 throw 'Node.js 24+ is required. Install the Windows release package or Node.js 24+.'
}
