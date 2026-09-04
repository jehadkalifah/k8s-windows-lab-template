$ErrorActionPreference = "Stop"

Write-Host "Creating golden-clean at BOTH levels (VM snapshots + Velero backup)..." -ForegroundColor Cyan
& "$PSScriptRoot\restore-point.ps1" create "golden-clean" -Level both

Write-Host ""
Write-Host "Golden restore point created." -ForegroundColor Green
Write-Host "VM restore:      .\scripts\restore-golden.ps1 -Level vm"
Write-Host "Cluster restore: .\scripts\restore-golden.ps1 -Level cluster"
