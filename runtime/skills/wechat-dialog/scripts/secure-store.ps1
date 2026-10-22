#requires -Version 5.1
param([ValidateSet('Read','Write')][string]$Mode, [string]$Path)
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = $OutputEncoding
[Console]::OutputEncoding = $OutputEncoding
try {
    Add-Type -AssemblyName System.Security
    if ($Mode -eq 'Write') {
        $raw = [Console]::In.ReadToEnd()
        $bytes = [Text.Encoding]::UTF8.GetBytes($raw)
        $encrypted = [Security.Cryptography.ProtectedData]::Protect($bytes, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
        [IO.File]::WriteAllBytes($Path, $encrypted)
        [Array]::Clear($bytes, 0, $bytes.Length)
    } else {
        $encrypted = [IO.File]::ReadAllBytes($Path)
        $bytes = [Security.Cryptography.ProtectedData]::Unprotect($encrypted, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
        [Console]::Out.Write([Text.Encoding]::UTF8.GetString($bytes))
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
    exit 0
} catch {
    [Console]::Error.WriteLine('Secure storage failed.')
    exit 1
}
