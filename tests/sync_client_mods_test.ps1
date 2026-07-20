$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$syncScript = Join-Path $projectRoot 'scripts\sync-client-mods.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ce-server-mod-test-" + [guid]::NewGuid().ToString('N'))
$clientRoot = Join-Path $testRoot 'client'
$serverMods = Join-Path $testRoot 'server-mods'
$clientModList = Join-Path $clientRoot 'modlist.txt'

if (-not (Test-Path -LiteralPath $syncScript -PathType Leaf)) {
    throw 'Mod sync script is missing'
}

New-Item -ItemType Directory -Path $clientRoot | Out-Null

try {
    $firstPak = Join-Path $clientRoot 'First.pak'
    $missingPak = Join-Path $clientRoot 'Missing.pak'
    $secondPak = Join-Path $clientRoot 'Second.pak'
    [System.IO.File]::WriteAllText($firstPak, 'first-content')
    [System.IO.File]::WriteAllText($secondPak, 'second-content')
    [System.IO.File]::WriteAllLines($clientModList, @(
        "*$firstPak",
        "*$missingPak",
        "*$secondPak"
    ))

    $missingWasRejected = $false
    try {
        & $syncScript -ClientModList $clientModList -ServerModsDir $serverMods -ErrorAction Stop | Out-Null
    }
    catch {
        $missingWasRejected = $true
    }
    if (-not $missingWasRejected) {
        throw 'Missing client PAK must be rejected unless -SkipMissing is specified'
    }

    & $syncScript -ClientModList $clientModList -ServerModsDir $serverMods -SkipMissing | Out-Null

    $serverModList = Join-Path $serverMods 'modlist.txt'
    $actualOrder = @(Get-Content -LiteralPath $serverModList)
    $expectedOrder = @('*First.pak', '*Second.pak')
    if (($actualOrder -join "`n") -ne ($expectedOrder -join "`n")) {
        throw "Server mod order is incorrect: $($actualOrder -join ', ')"
    }

    if ((Get-Content -Raw -LiteralPath (Join-Path $serverMods 'First.pak')) -ne 'first-content') {
        throw 'First PAK was not copied correctly'
    }
    if ((Get-Content -Raw -LiteralPath (Join-Path $serverMods 'Second.pak')) -ne 'second-content') {
        throw 'Second PAK was not copied correctly'
    }

    $bytes = [System.IO.File]::ReadAllBytes($serverModList)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw 'Server modlist.txt must be UTF-8 without BOM'
    }

    $isolatedProject = Join-Path $testRoot 'isolated-project'
    $isolatedScripts = Join-Path $isolatedProject 'scripts'
    $isolatedScript = Join-Path $isolatedScripts 'sync-client-mods.ps1'
    New-Item -ItemType Directory -Path $isolatedScripts | Out-Null
    Copy-Item -LiteralPath $syncScript -Destination $isolatedScript
    & powershell -NoProfile -ExecutionPolicy Bypass -File $isolatedScript -ClientModList $clientModList -SkipMissing | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Sync script must support direct powershell -File execution with the default server path'
    }
    $isolatedModList = Join-Path $isolatedProject 'data\ConanSandbox\Mods\modlist.txt'
    if (-not (Test-Path -LiteralPath $isolatedModList -PathType Leaf)) {
        throw 'Default server mods path must resolve below the project containing the sync script'
    }

    Write-Output 'client mod sync tests passed'
}
finally {
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    $resolvedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolvedTestRoot.StartsWith($resolvedTempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
