$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$configFile = Join-Path $PSScriptRoot "lab-config.ps1"

if (Test-Path $configFile) {
    . $configFile
}

Push-Location $RepoRoot

try {
    Write-Host "Gracefully shutting down all Kubernetes lab VMs..." -ForegroundColor Cyan

    vagrant halt

    if ($LASTEXITCODE -ne 0) {
        throw "vagrant halt failed with exit code $LASTEXITCODE."
    }

    Write-Host ""
    Write-Host "Lab is powered off; VMs, disks, data, and snapshots are kept." -ForegroundColor Green
    Write-Host "Start it again with: .\scripts\run.ps1"
}
finally {
    Pop-Location
}
