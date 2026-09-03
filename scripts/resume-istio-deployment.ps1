$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot\load-config.ps1"

Push-Location $RepoRoot
try {
    Write-Host "Current Istio/MetalLB state:" -ForegroundColor Cyan
    vagrant ssh k3s-master -c "sudo helm list -A"
    vagrant ssh k3s-master -c "sudo kubectl -n metallb-system get ipaddresspool,l2advertisement"
    Write-Host ""
    Write-Host "Resuming the idempotent Istio Stage 2 deployment..." -ForegroundColor Cyan

    & "$PSScriptRoot\deploy.ps1" istio
}
finally {
    Pop-Location
}
