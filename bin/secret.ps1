#!/usr/bin/env pwsh
# secret.ps1 — Windows Credential Manager wrapper for agent-managed secrets
#
# Mirrors the macOS `secret` script (Keychain-backed) but stores entries in
# Windows Credential Manager via the native Win32 Credential API (Advapi32.dll),
# so no extra module install is needed.
#
# All entries share TargetName prefix "agent-secrets:" so `list` can use
# CredEnumerate's native wildcard filter — no manual dump-and-parse needed.
#
# Usage:
#   secret.ps1 list                   List all managed secret names
#   secret.ps1 list -l | --long       List names + descriptions (table)
#   secret.ps1 get <name>              Print value to stdout (no trailing newline)
#   secret.ps1 add <name> [desc]       Add new secret
#   secret.ps1 update <name> [desc]    Update existing secret
#   secret.ps1 rm <name>               Delete a secret
#   secret.ps1 -V | --version          Print version
#   secret.ps1 -h | --help             Show this help

$ErrorActionPreference = 'Stop'

$Version = '0.2.0'
$Prefix  = 'agent-secrets:'

# --- Win32 Credential Manager P/Invoke --------------------------------------
# ponytail: native Win32 API via Add-Type, not an installed module — mirrors
# the macOS version's use of the built-in `security` CLI, zero new deps.
$signature = @'
using System;
using System.Runtime.InteropServices;

public static class CredMan
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct CREDENTIAL
    {
        public int Flags;
        public int Type;
        public string TargetName;
        public string Comment;
        public long LastWritten;
        public int CredentialBlobSize;
        public IntPtr CredentialBlob;
        public int Persist;
        public int AttributeCount;
        public IntPtr Attributes;
        public string TargetAlias;
        public string UserName;
    }

    [DllImport("Advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr);

    [DllImport("Advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CredWrite([In] ref CREDENTIAL credential, [In] int flags);

    [DllImport("Advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CredDelete(string target, int type, int flags);

    [DllImport("Advapi32.dll", EntryPoint = "CredEnumerateW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CredEnumerate(string filter, int flag, out int count, out IntPtr pCredentials);

    [DllImport("Advapi32.dll", EntryPoint = "CredFree", SetLastError = true)]
    public static extern void CredFree(IntPtr buffer);
}
'@
Add-Type -TypeDefinition $signature -ErrorAction Stop

$CRED_TYPE_GENERIC          = 1
$CRED_PERSIST_LOCAL_MACHINE = 2

function Get-RawCredential {
    param([Parameter(Mandatory)][string]$TargetName)
    $ptr = [IntPtr]::Zero
    if (-not [CredMan]::CredRead($TargetName, $CRED_TYPE_GENERIC, 0, [ref]$ptr)) {
        return $null
    }
    try {
        $cred = [System.Runtime.InteropServices.Marshal]::PtrToStructure($ptr, [type][CredMan+CREDENTIAL])
        $value = ''
        if ($cred.CredentialBlobSize -gt 0) {
            $bytes = New-Object byte[] $cred.CredentialBlobSize
            [System.Runtime.InteropServices.Marshal]::Copy($cred.CredentialBlob, $bytes, 0, $cred.CredentialBlobSize)
            $value = [System.Text.Encoding]::Unicode.GetString($bytes)
        }
        return [pscustomobject]@{
            TargetName = $cred.TargetName
            Comment    = $cred.Comment
            Value      = $value
        }
    } finally {
        [CredMan]::CredFree($ptr)
    }
}

function Write-Credential {
    param([string]$TargetName, [string]$Value, [string]$Comment)
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($Value)
    if ($bytes.Length -gt 512) {
        throw "Secret is too large for Windows Credential Manager (maximum: 512 bytes; actual: $($bytes.Length) bytes)"
    }
    $blobPtr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal([Math]::Max($bytes.Length, 1))
    try {
        if ($bytes.Length -gt 0) {
            [System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $blobPtr, $bytes.Length)
        }
        $cred = New-Object CredMan+CREDENTIAL
        $cred.Type = $CRED_TYPE_GENERIC
        $cred.TargetName = $TargetName
        $cred.Comment = $Comment
        $cred.CredentialBlobSize = $bytes.Length
        $cred.CredentialBlob = $blobPtr
        $cred.Persist = $CRED_PERSIST_LOCAL_MACHINE
        $cred.UserName = $Prefix.TrimEnd(':')
        if (-not [CredMan]::CredWrite([ref]$cred, 0)) {
            throw "CredWrite failed: Win32 error $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
        }
    } finally {
        [System.Runtime.InteropServices.Marshal]::FreeHGlobal($blobPtr)
    }
}

# --- helpers -----------------------------------------------------------------

function Read-SecretValue {
    param([string]$Name)
    if ([Console]::IsInputRedirected) {
        $val = [Console]::In.ReadLine()
    } else {
        $secure = Read-Host -Prompt "Enter value for '$Name'" -AsSecureString
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try {
            $val = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        } finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
    if ([string]::IsNullOrEmpty($val)) {
        [Console]::Error.WriteLine("ERROR: empty value not allowed")
        exit 1
    }
    return $val
}

function Show-Usage {
    param([string]$Dest = 'stderr')
    $body = @'
secret.ps1 — Windows Credential Manager wrapper for agent-managed secrets

All entries share TargetName prefix "agent-secrets:" so `list` filters out
unrelated credentials. Designed for scripted/agent use: `get` fails loudly
instead of returning empty on missing entries.

Usage:
  secret.ps1 list                   List all managed secret names
  secret.ps1 list -l | --long       List names + descriptions (table)
  secret.ps1 get <name>              Print value to stdout
                                     (no trailing newline, exits 1 if missing)
  secret.ps1 add <name> [desc]       Add new secret
                                     Value: hidden prompt if interactive, else stdin
                                     Desc:  optional, stored as credential comment
  secret.ps1 update <name> [desc]    Update existing secret
                                     Desc omitted => existing description kept
  secret.ps1 rm <name>               Delete a secret
  secret.ps1 -V | --version          Print version
  secret.ps1 -h | --help             Show this help

Examples:
  # Add with description
  secret.ps1 add aliyun-main-access-key-id "阿里云主账号 access key id"

  # Use in a command without exporting to the session
  $env:ALIBABA_CLOUD_ACCESS_KEY_ID = & secret.ps1 get aliyun-main-access-key-id

  # Browse what exists
  secret.ps1 list -l

Storage: Windows Credential Manager (Control Panel > Credential Manager > Windows Credentials)
         Unlocked automatically under the current Windows user profile.
'@
    if ($Dest -eq 'stdout') { Write-Output $body } else { [Console]::Error.WriteLine($body) }
}

# --- commands ------------------------------------------------------------

function Invoke-List {
    param([string]$Flag)
    $long = $false
    switch ($Flag) {
        { $_ -in '-l', '--long' } { $long = $true }
        '' { }
        default { [Console]::Error.WriteLine("Unknown flag for list: $Flag"); exit 1 }
    }

    $count = 0
    $ptr = [IntPtr]::Zero
    $ok = [CredMan]::CredEnumerate("$Prefix*", 0, [ref]$count, [ref]$ptr)
    if (-not $ok) {
        if ($long) { Write-Output "NAME`tDESCRIPTION" }
        return
    }
    try {
        $rows = for ($i = 0; $i -lt $count; $i++) {
            $elemPtr = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($ptr, $i * [IntPtr]::Size)
            $cred = [System.Runtime.InteropServices.Marshal]::PtrToStructure($elemPtr, [type][CredMan+CREDENTIAL])
            [pscustomobject]@{
                Name        = $cred.TargetName.Substring($Prefix.Length)
                Description = $cred.Comment
            }
        }
        $rows = $rows | Sort-Object Name
        if ($long) {
            Write-Output "NAME`tDESCRIPTION"
            $rows | ForEach-Object { Write-Output "$($_.Name)`t$($_.Description)" }
        } else {
            $rows | ForEach-Object { Write-Output $_.Name }
        }
    } finally {
        [CredMan]::CredFree($ptr)
    }
}

function Invoke-Get {
    param([string]$Name)
    if (-not $Name) { [Console]::Error.WriteLine("secret name required"); exit 1 }
    $cred = Get-RawCredential -TargetName "$Prefix$Name"
    if (-not $cred) {
        [Console]::Error.WriteLine("ERROR: secret '$Name' not found or locked")
        exit 1
    }
    $val = $cred.Value
    if ([string]::IsNullOrEmpty($val)) {
        [Console]::Error.WriteLine("ERROR: secret '$Name' is empty")
        exit 1
    }
    [Console]::Out.Write($val)
}

function Invoke-Add {
    param([string]$Name, [string]$Desc)
    if (-not $Name) { [Console]::Error.WriteLine("secret name required"); exit 1 }
    if (Get-RawCredential -TargetName "$Prefix$Name") {
        [Console]::Error.WriteLine("ERROR: secret '$Name' already exists. Use 'secret.ps1 update $Name'.")
        exit 1
    }
    $val = Read-SecretValue -Name $Name
    Write-Credential -TargetName "$Prefix$Name" -Value $val -Comment $Desc
    [Console]::Error.WriteLine("Added: $Name")
}

function Invoke-Update {
    param([string]$Name, [string]$Desc)
    if (-not $Name) { [Console]::Error.WriteLine("secret name required"); exit 1 }
    $existing = Get-RawCredential -TargetName "$Prefix$Name"
    if (-not $existing) {
        [Console]::Error.WriteLine("ERROR: secret '$Name' does not exist. Use 'secret.ps1 add $Name'.")
        exit 1
    }
    if (-not $Desc) { $Desc = $existing.Comment }
    $val = Read-SecretValue -Name $Name
    Write-Credential -TargetName "$Prefix$Name" -Value $val -Comment $Desc
    [Console]::Error.WriteLine("Updated: $Name")
}

function Invoke-Rm {
    param([string]$Name)
    if (-not $Name) { [Console]::Error.WriteLine("secret name required"); exit 1 }
    if (-not [CredMan]::CredDelete("$Prefix$Name", $CRED_TYPE_GENERIC, 0)) {
        [Console]::Error.WriteLine("ERROR: secret '$Name' not found")
        exit 1
    }
    [Console]::Error.WriteLine("Deleted: $Name")
}

# --- dispatch ------------------------------------------------------------

$cmd = $args[0]
switch ($cmd) {
    'list'                          { Invoke-List -Flag $args[1] }
    'get'                           { Invoke-Get -Name $args[1] }
    'add'                           { Invoke-Add -Name $args[1] -Desc $args[2] }
    'update'                        { Invoke-Update -Name $args[1] -Desc $args[2] }
    { $_ -in 'rm', 'delete' }       { Invoke-Rm -Name $args[1] }
    { $_ -in '-V', '--version', 'version' } { Write-Output "secret $Version" }
    { $_ -in '-h', '--help' }       { Show-Usage -Dest 'stdout' }
    $null                          { Show-Usage; exit 1 }
    default                        { [Console]::Error.WriteLine("Unknown command: $cmd"); Show-Usage; exit 1 }
}
