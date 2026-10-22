#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Register','Create','Prepare','Relocate','Login','Connect','Start','Stop','Status','Smoke','SendFile','SendProjectFile','Info','List')]
    [string]$Action = 'Status',
    [ValidatePattern('^[a-z][a-z0-9-]{0,47}$')][string]$Name = 'primary',
    [string]$Workspace,
    [string]$TemplateWorkspace,
    [string]$CodexPath,
    [string]$NodePath,
    [string]$AttachmentPath,
    [string]$EventId,
    [string]$ProjectId,
    [string]$SourceThreadId,
    [string]$Caption = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $OutputEncoding
$registryRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Codex\wechat-dialog-instances'
$configPath = Join-Path $registryRoot ($Name + '.json')
$botScript = Join-Path $PSScriptRoot 'wechat-bot.mjs'
function Write-InstanceResult($Value) { [Console]::Out.WriteLine(($Value | ConvertTo-Json -Depth 10 -Compress)) }
function Resolve-Node {
    if ($NodePath -and (Test-Path -LiteralPath $NodePath -PathType Leaf)) { return $NodePath }
    $runtimeConfig = Join-Path (Split-Path $PSScriptRoot -Parent) 'runtime-config.json'
    if (Test-Path -LiteralPath $runtimeConfig) {
        $runtime = [IO.File]::ReadAllText($runtimeConfig, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if ($runtime.node -and (Test-Path -LiteralPath $runtime.node -PathType Leaf)) { return $runtime.node }
    }
    $found = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }
    throw 'NODE_NOT_FOUND'
}
function Resolve-Codex {
    if ($CodexPath -and (Test-Path -LiteralPath $CodexPath -PathType Leaf)) { return $CodexPath }
    if ($env:CODEX_CLI_PATH -and (Test-Path -LiteralPath $env:CODEX_CLI_PATH -PathType Leaf)) { return $env:CODEX_CLI_PATH }
    $found = Get-Command codex.exe -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }
    throw 'CODEX_NOT_FOUND'
}
function Read-Instance([string]$InstanceName) {
    $file = Join-Path $registryRoot ($InstanceName + '.json')
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw 'INSTANCE_NOT_REGISTERED' }
    $value = [IO.File]::ReadAllText($file, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if ($value.name -ne $InstanceName -or -not [IO.Path]::IsPathRooted($value.data_directory) -or -not [IO.Path]::IsPathRooted($value.workspace)) { throw 'INVALID_INSTANCE_CONFIG' }
    return $value
}
function Invoke-InstanceBot($Config, [string[]]$BotArguments) {
    $oldDir = $env:CODEX_WECHAT_DATA_DIR; $oldName = $env:CODEX_WECHAT_INSTANCE
    try {
        $env:CODEX_WECHAT_DATA_DIR = $Config.data_directory
        $env:CODEX_WECHAT_INSTANCE = $Config.name
        $raw = & (Resolve-Node) $botScript @BotArguments
        $result = @($raw)[-1] | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0 -or (($result.PSObject.Properties.Name -contains 'status') -and $result.status -eq 'error')) { throw 'INSTANCE_OPERATION_FAILED' }
        return $result
    } finally { $env:CODEX_WECHAT_DATA_DIR = $oldDir; $env:CODEX_WECHAT_INSTANCE = $oldName }
}
try {
    if ($Action -eq 'List') {
        $instances = @()
        if (Test-Path -LiteralPath $registryRoot) {
            foreach ($file in Get-ChildItem -LiteralPath $registryRoot -Filter '*.json' -File) {
                $config = Read-Instance $file.BaseName
                $instances += @{ name = $config.name; workspace = $config.workspace; data_directory = $config.data_directory;
                    status = (Invoke-InstanceBot $config @('status')) }
            }
        }
        Write-InstanceResult @{ status = 'instances'; notification_recipient = 'primary'; instances = $instances }
        exit 0
    }
    if ($Action -in @('Register','Create')) {
        if ([string]::IsNullOrWhiteSpace($Workspace)) { throw 'WORKSPACE_REQUIRED' }
        $Workspace = [IO.Path]::GetFullPath($Workspace)
        if ($Workspace.TrimEnd('\') -eq [IO.Path]::GetPathRoot($Workspace).TrimEnd('\')) { throw 'WORKSPACE_ROOT_FORBIDDEN' }
        $directory = if ($Name -eq 'primary') {
            Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Codex\wechat-dialog'
        } else { Join-Path $registryRoot $Name }
        if (Test-Path -LiteralPath $configPath) {
            $previous = Read-Instance $Name
            if ($previous.workspace -ne $Workspace -or $previous.data_directory -ne $directory) { throw 'INSTANCE_CONFIG_CONFLICT' }
        }
        if (Test-Path -LiteralPath $registryRoot) {
            foreach ($file in Get-ChildItem -LiteralPath $registryRoot -Filter '*.json' -File) {
                $other = Read-Instance $file.BaseName
                if ($other.name -ne $Name -and ($other.workspace -eq $Workspace -or $other.data_directory -eq $directory)) { throw 'INSTANCE_DIRECTORY_CONFLICT' }
            }
        }
        if ($Action -eq 'Create') {
            if ($Name -eq 'primary') { throw 'USE_REGISTER_FOR_PRIMARY' }
            $marker = Join-Path $Workspace '.wechat-instance.json'
            if ((Test-Path -LiteralPath $Workspace) -and -not (Test-Path -LiteralPath $marker)) { throw 'EXISTING_WORKSPACE_NOT_MANAGED' }
            if ((Test-Path -LiteralPath $marker) -and (([IO.File]::ReadAllText($marker) | ConvertFrom-Json).name -ne $Name)) { throw 'INSTANCE_MARKER_CONFLICT' }
            if ($TemplateWorkspace) {
                $sourceAgents = Join-Path $TemplateWorkspace 'AGENTS.md'
                $sourcePersona = Join-Path $TemplateWorkspace 'outputs\persona'
                if (-not (Test-Path -LiteralPath $sourceAgents) -or -not (Test-Path -LiteralPath $sourcePersona)) { throw 'TEMPLATE_NOT_FOUND' }
            }
            [void][IO.Directory]::CreateDirectory($Workspace)
            [void][IO.Directory]::CreateDirectory((Join-Path $Workspace 'work'))
            [void][IO.Directory]::CreateDirectory((Join-Path $Workspace 'outputs'))
            if ($TemplateWorkspace -and -not (Test-Path -LiteralPath $marker)) {
                Copy-Item -LiteralPath $sourceAgents -Destination (Join-Path $Workspace 'AGENTS.md')
                Copy-Item -LiteralPath $sourcePersona -Destination (Join-Path $Workspace 'outputs\persona') -Recurse
            }
            [IO.File]::WriteAllText($marker, (@{ name = $Name; managed = $true } | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
        }
        $config = @{ name = $Name; workspace = $Workspace; data_directory = $directory; notification_recipient = 'primary' }
        [void][IO.Directory]::CreateDirectory($registryRoot)
        $temporary = $configPath + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
        [IO.File]::WriteAllText($temporary, ($config | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $configPath -Force
        Write-InstanceResult @{ status = 'registered'; instance = $config }
        exit 0
    }
    $config = Read-Instance $Name
    if ($Action -eq 'Relocate') {
        if ([string]::IsNullOrWhiteSpace($Workspace) -or -not (Test-Path -LiteralPath $Workspace -PathType Container)) { throw 'WORKSPACE_REQUIRED' }
        $Workspace = [IO.Path]::GetFullPath($Workspace).TrimEnd('\')
        if ($Workspace -eq [IO.Path]::GetPathRoot($Workspace).TrimEnd('\')) { throw 'WORKSPACE_ROOT_FORBIDDEN' }
        $config.workspace = $Workspace
        $prepared = Invoke-InstanceBot $config @('prepare','--cwd',$Workspace)
        $temporary = $configPath + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
        [IO.File]::WriteAllText($temporary, ($config | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $configPath -Force
        Write-InstanceResult @{ status = 'relocated'; instance = $config; preparation = $prepared }
        exit 0
    }
    if ($Action -eq 'Info') { Write-InstanceResult $config; exit 0 }
    $result = switch ($Action) {
        'Prepare' { Invoke-InstanceBot $config @('prepare','--cwd',$config.workspace,'--codex',(Resolve-Codex)) }
        'Login' { Invoke-InstanceBot $config @('login','--qr',(Join-Path $config.workspace 'outputs\wechat-clawbot-login.png'),'--show-qr') }
        'Connect' {
            $current = Invoke-InstanceBot $config @('status')
            if (-not ($current.PSObject.Properties.Name -contains 'logged_in') -or -not $current.logged_in) {
                $logged = Invoke-InstanceBot $config @('login','--qr',(Join-Path $config.workspace 'outputs\wechat-clawbot-login.png'),'--show-qr')
                if ($logged.status -ne 'logged_in') { Write-InstanceResult $logged; exit 1 }
            }
            Invoke-InstanceBot $config @('start')
        }
        'Smoke' { Invoke-InstanceBot $config @('smoke') }
        'SendFile' {
            if ([string]::IsNullOrWhiteSpace($AttachmentPath) -or [string]::IsNullOrWhiteSpace($EventId)) { throw 'FILE_AND_EVENT_REQUIRED' }
            $fileArguments = @('send-file','--file',$AttachmentPath,'--event',$EventId)
            if ($Caption) { $fileArguments += @('--caption',$Caption) }
            Invoke-InstanceBot $config $fileArguments
        }
        'SendProjectFile' {
            if ([string]::IsNullOrWhiteSpace($AttachmentPath) -or [string]::IsNullOrWhiteSpace($EventId) -or [string]::IsNullOrWhiteSpace($ProjectId) -or [string]::IsNullOrWhiteSpace($SourceThreadId)) { throw 'PROJECT_FILE_ARGUMENTS_REQUIRED' }
            $fileArguments = @('send-project-file','--file',$AttachmentPath,'--event',$EventId,'--project',$ProjectId,'--thread',$SourceThreadId)
            if ($Caption) { $fileArguments += @('--caption',$Caption) }
            Invoke-InstanceBot $config $fileArguments
        }
        'Start' { Invoke-InstanceBot $config @('start') }
        'Stop' { Invoke-InstanceBot $config @('stop') }
        'Status' { Invoke-InstanceBot $config @('status') }
    }
    Write-InstanceResult $result
} catch {
    $code = if ($_.Exception.Message -match '^[A-Z][A-Z0-9_]+$') { $_.Exception.Message } else { 'INSTANCE_LOCAL_ERROR' }
    Write-InstanceResult @{ status = 'error'; code = $code; instance = $Name }
    exit 1
}
