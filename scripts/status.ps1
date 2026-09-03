$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $RepoRoot
try {
    Write-Host "=== Vagrant ===" -ForegroundColor Cyan
    vagrant status

    Write-Host ""
    Write-Host "=== Kubernetes nodes ===" -ForegroundColor Cyan
    vagrant ssh k3s-master -c "sudo kubectl get nodes -o wide"

    Write-Host ""
    Write-Host "=== Namespaces ===" -ForegroundColor Cyan
    vagrant ssh k3s-master -c "sudo kubectl get ns"

    Write-Host ""
    Write-Host "=== Pods ===" -ForegroundColor Cyan
    vagrant ssh k3s-master -c "sudo kubectl get pods -A"

    Write-Host ""
    Write-Host "=== Flannel ===" -ForegroundColor Cyan
    try {
        & "$PSScriptRoot\check-flannel.ps1"
    }
    catch {
        Write-Host "FLANNEL CHECK FAILED: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "Stage 2 status:" -ForegroundColor DarkGray
    Write-Host "  .\scripts\deployment-status.ps1 istio"
}
finally {
    Pop-Location
}
