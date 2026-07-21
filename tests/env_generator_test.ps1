$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$generator = Join-Path $projectRoot 'scripts\generate-env.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ce-server-env-test-" + [guid]::NewGuid().ToString('N'))
$envPath = Join-Path $testRoot '.env'

New-Item -ItemType Directory -Path $testRoot | Out-Null

try {
    & $generator -OutputPath $envPath | Out-Null

    if (-not (Test-Path -LiteralPath $envPath -PathType Leaf)) {
        throw '.env was not generated'
    }

    $settings = @{}
    foreach ($line in Get-Content -LiteralPath $envPath) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
            continue
        }

        $parts = $line.Split('=', 2)
        if ($parts.Count -ne 2) {
            throw 'Generated .env contains an invalid line'
        }
        $settings[$parts[0]] = $parts[1]
    }

    $requiredKeys = @(
        'STEAM_UID',
        'STEAM_GID',
        'UPDATE_ON_START',
        'MOD_WORKSHOP_ITEMS',
        'SERVER_NAME',
        'ADMIN_PASSWORD',
        'GAME_PORT',
        'PING_PORT',
        'QUERY_PORT',
        'MAX_PLAYERS',
        'RCON_ENABLED',
        'RCON_PORT',
        'RCON_PASSWORD'
    )

    foreach ($key in $requiredKeys) {
        if (-not $settings.ContainsKey($key)) {
            throw "Missing required key: $key"
        }
    }

    if ($settings.ContainsKey('SERVER_PASSWORD')) {
        throw 'Generated .env must not configure SERVER_PASSWORD; compose keeps the join password disabled'
    }

    $secretKeys = @('ADMIN_PASSWORD', 'RCON_PASSWORD')
    $secretFingerprints = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($key in $secretKeys) {
        $secret = $settings[$key]
        if ($secret -notmatch '^[A-Za-z0-9_-]{32,}$') {
            throw "$key is not a strong URL-safe secret"
        }
        if (-not $secretFingerprints.Add($secret)) {
            throw 'Generated secrets must be unique'
        }
    }

    if ($settings['RCON_ENABLED'] -ne 'false') {
        throw 'RCON must remain disabled by default'
    }

    $expectedMods = @(
        '3720904511:BetterThralls.pak',
        '3719642461:Xev_HearthStone.pak',
        '3718523921:Thrall_Commander.pak',
        '3720737911:ExtendedThrallStatsEnhanced.pak',
        '3719585133:DamageNumber.pak',
        '3719513784:Simple_Minimap.pak',
        '3720915336:StacksizePlus.pak',
        '3719604490:Retro_Purge.pak'
    ) -join ','
    if ($settings['MOD_WORKSHOP_ITEMS'] -ne $expectedMods) {
        throw 'Generated .env must configure the current eight mods in client load order'
    }

    $bytes = [System.IO.File]::ReadAllBytes($envPath)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw 'Generated .env must be UTF-8 without BOM'
    }

    $overwriteWasRejected = $false
    try {
        & $generator -OutputPath $envPath -ErrorAction Stop | Out-Null
    }
    catch {
        $overwriteWasRejected = $true
    }
    if (-not $overwriteWasRejected) {
        throw 'Generator must refuse to overwrite an existing .env without -Force'
    }

    & $generator -OutputPath $envPath -Force | Out-Null

    $isolatedProject = Join-Path $testRoot 'isolated-project'
    $isolatedScripts = Join-Path $isolatedProject 'scripts'
    $isolatedGenerator = Join-Path $isolatedScripts 'generate-env.ps1'
    New-Item -ItemType Directory -Path $isolatedScripts | Out-Null
    Copy-Item -LiteralPath $generator -Destination $isolatedGenerator
    & powershell -NoProfile -ExecutionPolicy Bypass -File $isolatedGenerator | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Generator must support direct powershell -File execution'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $isolatedProject '.env') -PathType Leaf)) {
        throw 'Generator default path must point to .env in the project root'
    }

    Write-Output 'env generator tests passed'
}
finally {
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    $resolvedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolvedTestRoot.StartsWith($resolvedTempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
