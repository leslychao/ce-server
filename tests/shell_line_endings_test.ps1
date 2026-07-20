$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$trackedShellScripts = @(& git -C $projectRoot ls-files -- '*.sh')

if ($LASTEXITCODE -ne 0) {
    throw 'Unable to enumerate tracked shell scripts'
}

if ($trackedShellScripts.Count -eq 0) {
    throw 'No tracked shell scripts found'
}

foreach ($relativePath in $trackedShellScripts) {
    $attribute = & git -C $projectRoot check-attr eol -- $relativePath
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read Git attributes for $relativePath"
    }
    if ($attribute -notmatch ': eol: lf$') {
        throw "$relativePath must be covered by a Git eol=lf rule"
    }

    $absolutePath = Join-Path $projectRoot $relativePath
    $bytes = [System.IO.File]::ReadAllBytes($absolutePath)
    if ([System.Array]::IndexOf($bytes, [byte]13) -ge 0) {
        throw "$relativePath contains CR bytes; shell scripts must use LF line endings"
    }
}

Write-Output "Shell script line-ending test passed ($($trackedShellScripts.Count) files)"
