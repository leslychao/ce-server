[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ClientModList = (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFilesX86)) 'Steam\steamapps\common\Conan Exiles\ConanSandbox\Mods\modlist.txt'),
    [string]$ServerModsDir = '',
    [switch]$SkipMissing
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($ServerModsDir)) {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $ServerModsDir = Join-Path $projectRoot 'data\ConanSandbox\Mods'
}

if (-not (Test-Path -LiteralPath $ClientModList -PathType Leaf)) {
    throw "Client modlist.txt was not found: $ClientModList"
}

$clientModListDir = Split-Path -Parent ([System.IO.Path]::GetFullPath($ClientModList))
$resolvedMods = [System.Collections.Generic.List[object]]::new()
$missingMods = [System.Collections.Generic.List[string]]::new()
$destinationNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

foreach ($rawLine in Get-Content -LiteralPath $ClientModList) {
    $entry = $rawLine.Trim()
    if ([string]::IsNullOrWhiteSpace($entry) -or $entry.StartsWith('#')) {
        continue
    }
    if ($entry.StartsWith('*')) {
        $entry = $entry.Substring(1)
    }
    if (-not [System.IO.Path]::IsPathRooted($entry)) {
        $entry = Join-Path $clientModListDir $entry
    }

    $sourcePath = [System.IO.Path]::GetFullPath($entry)
    if ([System.IO.Path]::GetExtension($sourcePath) -ne '.pak') {
        throw "Client mod entry is not a .pak file: $sourcePath"
    }
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        $missingMods.Add($sourcePath)
        continue
    }

    $destinationName = [System.IO.Path]::GetFileName($sourcePath)
    if (-not $destinationNames.Add($destinationName)) {
        throw "Duplicate destination PAK name in client modlist.txt: $destinationName"
    }
    $resolvedMods.Add([pscustomobject]@{
        SourcePath = $sourcePath
        FileName = $destinationName
    })
}

if ($missingMods.Count -gt 0 -and -not $SkipMissing) {
    throw "Client modlist.txt references missing PAK files: $($missingMods -join ', ')"
}
foreach ($missingMod in $missingMods) {
    Write-Warning "Skipping missing client PAK: $missingMod"
}
if ($resolvedMods.Count -eq 0) {
    throw 'Client modlist.txt does not contain any available PAK files'
}

$serverModsFullPath = [System.IO.Path]::GetFullPath($ServerModsDir)
if ($PSCmdlet.ShouldProcess($serverModsFullPath, "Copy $($resolvedMods.Count) PAK files and replace modlist.txt")) {
    New-Item -ItemType Directory -Path $serverModsFullPath -Force | Out-Null

    foreach ($mod in $resolvedMods) {
        $destinationPath = Join-Path $serverModsFullPath $mod.FileName
        $temporaryPath = "$destinationPath.$([guid]::NewGuid().ToString('N')).tmp"
        try {
            [System.IO.File]::Copy($mod.SourcePath, $temporaryPath, $true)
            Move-Item -LiteralPath $temporaryPath -Destination $destinationPath -Force
        }
        finally {
            if (Test-Path -LiteralPath $temporaryPath) {
                Remove-Item -LiteralPath $temporaryPath -Force
            }
        }
    }

    $serverModList = Join-Path $serverModsFullPath 'modlist.txt'
    $temporaryModList = "$serverModList.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $lines = @($resolvedMods | ForEach-Object { "*$($_.FileName)" })
        [System.IO.File]::WriteAllLines($temporaryModList, $lines, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporaryModList -Destination $serverModList -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryModList) {
            Remove-Item -LiteralPath $temporaryModList -Force
        }
    }
}

[pscustomobject]@{
    ClientModList = [System.IO.Path]::GetFullPath($ClientModList)
    ServerModsDir = $serverModsFullPath
    InstalledCount = $resolvedMods.Count
    SkippedMissingCount = $missingMods.Count
    LoadOrder = @($resolvedMods | ForEach-Object { $_.FileName })
}
