$ErrorActionPreference = "Stop"
& "$PSScriptRoot\vm-points.ps1" create "golden-clean"

Write-Host ""
Write-Host "Golden VM restore point created." -ForegroundColor Green
Write-Host "Restore it with: .\scripts\restore-golden.ps1"
