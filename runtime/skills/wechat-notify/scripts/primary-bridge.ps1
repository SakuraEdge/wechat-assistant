#requires -Version 5.1
# Only the child process receives the notification route. The caller's instance
# environment remains untouched, including when this file is dot-sourced.
function Get-PrimaryWechatRoute {
    param([string]$RouteFile = (Join-Path (Split-Path $PSScriptRoot -Parent) 'notification-route.json'))
    $directory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Codex\wechat-dialog'
    if (Test-Path -LiteralPath $RouteFile) {
        $route = [IO.File]::ReadAllText($RouteFile, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if ($route.recipient_instance -ne 'primary' -or $route.mode -ne 'primary_only' -or
            -not [IO.Path]::IsPathRooted([string]$route.data_directory)) { throw 'INVALID_PRIMARY_ROUTE' }
        $directory = [IO.Path]::GetFullPath([string]$route.data_directory)
    }
    return [pscustomobject]@{ recipient_instance = 'primary'; mode = 'primary_only'; data_directory = $directory }
}

function Invoke-PrimaryWechatBridge {
    param([string]$Node, [string]$Script, [ValidateSet('status','send')][string]$Command, [string]$MessageFile,
          [string]$RouteFile = (Join-Path (Split-Path $PSScriptRoot -Parent) 'notification-route.json'))
    $route = Get-PrimaryWechatRoute -RouteFile $RouteFile
    $arguments = @($Script, $Command)
    if ($Command -eq 'send') { $arguments += @('--message', $MessageFile) }
    foreach ($argument in $arguments) {
        if ([string]::IsNullOrWhiteSpace($argument) -or $argument -match '["\r\n]' -or $argument.EndsWith('\')) { throw 'INVALID_BRIDGE_ARGUMENT' }
    }
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $Node
    $info.Arguments = (($arguments | ForEach-Object { '"' + $_ + '"' }) -join ' ')
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $info.EnvironmentVariables['CODEX_WECHAT_DATA_DIR'] = $route.data_directory
    $info.EnvironmentVariables['CODEX_WECHAT_INSTANCE'] = 'primary'
    $child = New-Object Diagnostics.Process
    $child.StartInfo = $info
    try {
        [void]$child.Start()
        $readOut = $child.StandardOutput.ReadToEndAsync()
        $readErr = $child.StandardError.ReadToEndAsync()
        if (-not $child.WaitForExit(30000)) { try { $child.Kill() } catch { }; throw 'PRIMARY_BRIDGE_TIMEOUT' }
        $result = $readOut.GetAwaiter().GetResult() | ConvertFrom-Json
        [void]$readErr.GetAwaiter().GetResult()
        if ($null -eq $result) { throw 'INVALID_BRIDGE_RESPONSE' }
        $result | Add-Member -NotePropertyName recipient_instance -NotePropertyValue 'primary' -Force
        return $result
    } finally { $child.Dispose() }
}
