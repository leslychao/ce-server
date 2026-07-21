$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $projectRoot 'compose.yaml'
$rconComposeFile = Join-Path $projectRoot 'compose.rcon.yaml'
$expectedItems = @(
    '3720904511:BetterThralls.pak'
    '3719642461:Xev_HearthStone.pak'
    '3718523921:Thrall_Commander.pak'
    '3720737911:ExtendedThrallStatsEnhanced.pak'
    '3719585133:DamageNumber.pak'
    '3719513784:Simple_Minimap.pak'
    '3720915336:StacksizePlus.pak'
    '3719604490:Retro_Purge.pak'
)

function Get-ComposeConfig {
    param(
        [string[]]$ComposeFiles = @()
    )

    $arguments = @('compose', '--project-directory', $projectRoot)
    foreach ($composeFilePath in $ComposeFiles) {
        $arguments += @('-f', $composeFilePath)
    }
    $arguments += @('config', '--format', 'json')

    $configJson = & docker @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "docker $($arguments -join ' ') failed"
    }

    return $configJson | ConvertFrom-Json
}

$config = Get-ComposeConfig

$actualItems = @($config.services.server.environment.MOD_WORKSHOP_ITEMS -split ',')
if (($actualItems -join "`n") -ne ($expectedItems -join "`n")) {
    throw "Compose must configure the current eight mods in client load order. Actual: $($actualItems -join ', ')"
}

if ($config.services.server.environment.SERVER_PASSWORD -ne '') {
    throw 'Default compose config must keep SERVER_PASSWORD empty'
}

$rconConfig = Get-ComposeConfig -ComposeFiles @($composeFile, $rconComposeFile)
if ($rconConfig.services.server.environment.SERVER_PASSWORD -ne '') {
    throw 'RCON compose config must keep SERVER_PASSWORD empty'
}

Write-Output 'compose configuration tests passed'
