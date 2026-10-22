#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Status', 'Configure', 'Preview', 'Send')]
    [string]$Action = 'Status',
    [string]$MessageFile,
    [string]$StateDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Codex\wechat-notify'),
    [switch]$SendTest
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$OutputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $OutputEncoding
. (Join-Path $PSScriptRoot 'primary-bridge.ps1')

function Write-Result {
    param([System.Collections.IDictionary]$Data)
    [Console]::Out.WriteLine(($Data | ConvertTo-Json -Depth 8 -Compress))
}

function Get-Hash {
    param([string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function Read-Token {
    if (-not [string]::IsNullOrWhiteSpace($env:WECHAT_PUSHPLUS_TOKEN)) {
        return $env:WECHAT_PUSHPLUS_TOKEN.Trim()
    }
    $credentialFile = Join-Path $StateDirectory 'token.xml'
    if (-not (Test-Path -LiteralPath $credentialFile)) { return $null }
    $secret = Import-Clixml -LiteralPath $credentialFile
    if ($secret -isnot [System.Security.SecureString]) { throw 'Invalid credential format.' }
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr).Trim() }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr); $secret.Dispose() }
}

function Read-Message {
    if ([string]::IsNullOrWhiteSpace($MessageFile)) { throw 'MessageFile is required.' }
    $inputMessage = Get-Content -LiteralPath $MessageFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $inputMessage -or $inputMessage -is [array]) { throw 'Expected one JSON object.' }
    $allowed = @('event_id', 'title', 'content')
    foreach ($property in $inputMessage.PSObject.Properties) {
        if ($property.Name -notin $allowed) { throw 'Unexpected message field.' }
    }
    foreach ($field in $allowed) {
        if ($null -eq $inputMessage.PSObject.Properties[$field]) { throw 'Required message field is missing.' }
        if ($inputMessage.$field -isnot [string] -or [string]::IsNullOrWhiteSpace($inputMessage.$field)) {
            throw 'All message fields must be nonempty strings.'
        }
    }
    if ($inputMessage.event_id.Length -gt 256 -or $inputMessage.title.Length -gt 100 -or $inputMessage.content.Length -gt 10000) {
        throw 'Message exceeds local size limits.'
    }
    return $inputMessage
}

function Save-Record {
    param([string]$Path, [System.Collections.IDictionary]$Record)
    # If update fails, the reservation still blocks automatic retransmission.
    [IO.File]::WriteAllText($Path, ($Record | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
}

function Send-Notification {
    param($Message)
    try { $token = Read-Token } catch {
        Write-Result @{ status = 'credential_error'; detail = 'Cannot decrypt local credential; configure again as this Windows user.' }
        return 1
    }
    if ([string]::IsNullOrWhiteSpace($token)) {
        Write-Result @{ status = 'not_configured'; detail = 'Run Configure locally to store a PushPlus token.' }
        return 1
    }
    $eventHash = Get-Hash $Message.event_id
    $payloadHash = Get-Hash (($Message.title, $Message.content) | ConvertTo-Json -Compress)
    $journalDirectory = Join-Path $StateDirectory 'events'
    [void][IO.Directory]::CreateDirectory($journalDirectory)
    $recordPath = Join-Path $journalDirectory ($eventHash + '.json')
    $record = [ordered]@{
        event_hash = $eventHash
        payload_hash = $payloadHash
        status = 'in_flight'
        time_utc = [DateTime]::UtcNow.ToString('o')
        receipt = $null
    }
    # CreateNew atomically reserves this event against concurrent senders.
    try { $reservation = [IO.File]::Open($recordPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None) }
    catch [IO.IOException] {
        if (-not (Test-Path -LiteralPath $recordPath)) { throw }
        $previousStatus = 'unknown'
        $receipt = $null
        $payloadChanged = $null
        try {
            $previous = Get-Content -LiteralPath $recordPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $previousStatus = $previous.status
            $receipt = $previous.receipt
            $payloadChanged = ($previous.payload_hash -ne $payloadHash)
        } catch { }
        Write-Result @{ status = 'duplicate'; previous_status = $previousStatus; receipt = $receipt; payload_changed = $payloadChanged; delivery = 'unconfirmed'; detail = 'No request sent; inspect prior outcome before any resend.' }
        if ($previousStatus -eq 'accepted') { return 0 }
        return 2
    }
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($record | ConvertTo-Json -Compress))
        $reservation.Write($bytes, 0, $bytes.Length)
        $reservation.Flush()
    } finally { $reservation.Dispose() }

    $payload = @{
        token = $token
        title = $Message.title
        content = $Message.content
        template = 'txt'
        channel = 'wechat'
    }
    try {
        $bodyBytes = [Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Compress))
        # Fixed HTTPS endpoint, no redirects or automatic retries.
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $response = Invoke-RestMethod -Uri 'https://www.pushplus.plus/send' -Method Post -ContentType 'application/json; charset=utf-8' -Body $bodyBytes -TimeoutSec 30 -MaximumRedirection 0
        if ($null -eq $response -or $null -eq $response.PSObject.Properties['code'] -or [string]$response.code -notmatch '^\d+$') {
            throw 'Invalid response.'
        }
        $code = [int]$response.code
        if ($code -eq 200) {
            $record.status = 'accepted'
            if ($null -ne $response.PSObject.Properties['data'] -and $response.data -is [string] -and $response.data -match '^[A-Za-z0-9_-]{1,128}$') {
                $record.receipt = $response.data
            }
            $recordSaved = $true
            try { Save-Record $recordPath $record } catch { $recordSaved = $false }
            Write-Result @{ status = 'accepted'; receipt = $record.receipt; record_saved = $recordSaved; delivery = 'unconfirmed'; detail = 'PushPlus accepted the request; WeChat delivery has not been verified. Preserve receipt if record_saved is false.' }
            return 0
        }
        $record.status = 'rejected'
        $record['api_code'] = $code
        $recordSaved = $true
        try { Save-Record $recordPath $record } catch { $recordSaved = $false }
        # Never echo raw provider responses, which may reflect user data.
        Write-Result @{ status = 'rejected'; api_code = $code; record_saved = $recordSaved; delivery = 'unconfirmed'; detail = 'PushPlus rejected the request; check its official return-code documentation.' }
        return 1
    } catch {
        $record.status = 'unknown'
        try { Save-Record $recordPath $record } catch { }
        Write-Result @{ status = 'unknown'; receipt = $record.receipt; delivery = 'unconfirmed'; detail = 'Request or local recording failed. It may have been sent; do not retry blindly.' }
        return 2
    } finally {
        $token = $null
        $payload = $null
        $bodyBytes = $null
    }
}

try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'This helper requires Windows.' }
    switch ($Action) {
        'Status' {
            $bridgeScript = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'wechat-dialog\scripts\wechat-bot.mjs'
            $bridgeNode = Resolve-PrimaryWechatNode
            if ((Test-Path -LiteralPath $bridgeScript) -and (Test-Path -LiteralPath $bridgeNode)) {
                try {
                    $bridgeStatus = Invoke-PrimaryWechatBridge -Node $bridgeNode -Script $bridgeScript -Command status
                    if ($bridgeStatus.running -and $bridgeStatus.reply_ready) {
                        Write-Result @{ status = 'status'; configured = $true; provider = 'clawbot'; recipient = 'self'; recipient_instance = 'primary'; delivery_verified = $false }
                        exit 0
                    }
                } catch { }
            }
            Write-Result @{ status = 'status'; configured = $false; provider = 'clawbot'; recipient_instance = 'primary'; detail = 'The primary instance must be running with a reply context. No fallback recipient is used.' }
            exit 0
        }
        'Configure' {
            # A Windows PowerShell child can inherit PowerShell 7's module path.
            # Load the matching built-in security module for DPAPI conversion.
            Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1') -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($env:WECHAT_PUSHPLUS_TOKEN)) {
                $secret = ConvertTo-SecureString -String $env:WECHAT_PUSHPLUS_TOKEN.Trim() -AsPlainText -Force
            } else {
                Write-Host 'Paste your own PushPlus token below. Input is hidden and is saved with Windows user encryption.'
                $secret = Read-Host -Prompt 'PushPlus token' -AsSecureString
            }
            if ($secret.Length -eq 0) { throw 'Empty token.' }
            [void][IO.Directory]::CreateDirectory($StateDirectory)
            try { $secret | Export-Clixml -LiteralPath (Join-Path $StateDirectory 'token.xml') -Encoding UTF8 }
            finally { $secret.Dispose() }
            Write-Result @{ status = 'configured'; provider = 'pushplus'; recipient = 'self'; delivery_verified = $false }
            if ($SendTest) {
                Write-Host 'Submitting one setup test to your own WeChat via PushPlus.'
                $testMessage = [pscustomobject]@{
                    event_id = 'setup-test:' + [Guid]::NewGuid().ToString('N')
                    title = 'Codex WeChat notification test'
                    content = 'Your Codex WeChat notification channel is configured. Please confirm receipt in WeChat.'
                }
                exit (Send-Notification $testMessage)
            }
            exit 0
        }
        'Preview' {
            $message = Read-Message
            Write-Result @{ status = 'preview'; recipient = 'self'; recipient_instance = 'primary'; provider = 'clawbot'; title = $message.title; content = $message.content; event_id = $message.event_id; network_used = $false }
            exit 0
        }
        'Send' {
            $message = Read-Message
            $bridgeScript = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'wechat-dialog\scripts\wechat-bot.mjs'
            $bridgeNode = Resolve-PrimaryWechatNode
            if ((Test-Path -LiteralPath $bridgeScript) -and (Test-Path -LiteralPath $bridgeNode)) {
                try {
                    $bridgeResult = Invoke-PrimaryWechatBridge -Node $bridgeNode -Script $bridgeScript -Command send -MessageFile $MessageFile
                    if ($bridgeResult.status -in @('queued', 'duplicate')) {
                        [Console]::Out.WriteLine(($bridgeResult | ConvertTo-Json -Compress))
                        exit 0
                    }
                    [Console]::Out.WriteLine(($bridgeResult | ConvertTo-Json -Compress))
                    exit 1
                } catch {
                    Write-Result @{ status = 'unknown'; recipient_instance = 'primary'; detail = 'Primary enqueue outcome is unknown. No fallback or automatic retry was attempted.' }
                    exit 2
                }
            }
            Write-Result @{ status = 'bridge_unavailable'; recipient_instance = 'primary'; detail = 'Primary bridge is unavailable. Other instances and PushPlus are not used for task notifications.' }
            exit 1
        }
    }
} catch {
    # Never echo arbitrary exceptions or input, which may contain secrets.
    Write-Result @{ status = 'local_error'; detail = 'Invalid input or local file operation failed. Check message schema, paths and permissions.' }
    exit 1
}
