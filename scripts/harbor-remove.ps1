param([switch]$Force)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $RepoRoot
try {
    if ($Force) {
        & "$PSScriptRoot\remove-deployment.ps1" harbor -Force
    }
    else {
        & "$PSScriptRoot\remove-deployment.ps1" harbor
    }
}
finally {
    Pop-Location
}
