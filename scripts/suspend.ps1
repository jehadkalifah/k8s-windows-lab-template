$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $RepoRoot

try {
    Write-Host "Suspending all Kubernetes lab VMs..." -ForegroundColor Cyan

    vagrant suspend

    if ($LASTEXITCODE -ne 0) {
        throw "vagrant suspend failed with exit code $LASTEXITCODE."
    }

    Write-Host ""
    Write-Host "Lab suspended successfully." -ForegroundColor Green
    Write-Host "Resume it with: .\scripts\resume.ps1"
}
finally {
    Pop-Location
}
