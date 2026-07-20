$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$dockerfile = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'Dockerfile')

if ($dockerfile.Contains('pgrep -f ConanSandboxServer-Linux-Shipping')) {
    throw 'Healthcheck pattern matches its own pgrep command line'
}

if (-not $dockerfile.Contains("pgrep -f '[C]onanSandboxServer-Linux-Shipping'")) {
    throw 'Healthcheck must use a self-excluding process pattern'
}

Write-Output 'Dockerfile healthcheck test passed'
