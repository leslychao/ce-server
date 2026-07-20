[CmdletBinding()]
param(
    [string]$OutputPath,

    [ValidateNotNullOrEmpty()]
    [string]$ServerName = 'Conan Exiles Enhanced Private Server',

    [ValidateRange(1, 200)]
    [int]$MaxPlayers = 20,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    $OutputPath = Join-Path (Split-Path -Parent $scriptDirectory) '.env'
}

function New-UrlSafeSecret {
    param(
        [ValidateRange(24, 128)]
        [int]$ByteCount = 32
    )

    $bytes = New-Object byte[] $ByteCount
    $random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $random.GetBytes($bytes)
    }
    finally {
        $random.Dispose()
    }

    return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Set-SecretFilePermissions {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
        $system = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-18')
        $allow = [System.Security.AccessControl.AccessControlType]::Allow
        $fullControl = [System.Security.AccessControl.FileSystemRights]::FullControl
        $acl = [System.Security.AccessControl.FileSecurity]::new()

        $acl.SetOwner($currentUser)
        $acl.SetAccessRuleProtection($true, $false)
        $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($currentUser, $fullControl, $allow))
        $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($system, $fullControl, $allow))
        [System.IO.File]::SetAccessControl($Path, $acl)
        return
    }

    & chmod 600 -- $Path
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not set mode 0600 on the generated .env file'
    }
}

$resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
if ((Test-Path -LiteralPath $resolvedOutputPath) -and -not $Force) {
    throw "Refusing to overwrite existing file: $resolvedOutputPath. Use -Force to rotate every secret."
}

$outputDirectory = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

$serverPassword = New-UrlSafeSecret
$adminPassword = New-UrlSafeSecret
$rconPassword = New-UrlSafeSecret

$lines = @(
    '# Generated locally by scripts/generate-env.ps1. Never commit or share this file.',
    'STEAM_UID=1000',
    'STEAM_GID=1000',
    '',
    'UPDATE_ON_START=true',
    'MOD_WORKSHOP_ITEMS=3720904511:BetterThralls.pak,3719642461:Xev_HearthStone.pak,3718523921:Thrall_Commander.pak,3720737911:ExtendedThrallStatsEnhanced.pak,3719585133:DamageNumber.pak,3719513784:Simple_Minimap.pak,3720915336:StacksizePlus.pak,3719604490:Retro_Purge.pak',
    '',
    "SERVER_NAME=$ServerName",
    "SERVER_PASSWORD=$serverPassword",
    "ADMIN_PASSWORD=$adminPassword",
    '',
    'GAME_PORT=7777',
    'PING_PORT=7778',
    'QUERY_PORT=27015',
    "MAX_PLAYERS=$MaxPlayers",
    '',
    '# RCON has a strong password prepared, but remains closed until explicitly enabled.',
    'RCON_ENABLED=false',
    'RCON_PORT=25575',
    "RCON_PASSWORD=$rconPassword"
)

$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
$content = [string]::Join("`n", $lines) + "`n"
[System.IO.File]::WriteAllText($resolvedOutputPath, $content, $utf8WithoutBom)
Set-SecretFilePermissions -Path $resolvedOutputPath

Write-Output 'Production .env created with unique generated secrets; values were not printed.'
