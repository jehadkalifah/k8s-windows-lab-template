$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ClusterVMs = @("k3s-master", "k3s-worker1", "k3s-worker2")

Push-Location $RepoRoot
try {
    Write-Host "=== Kubernetes Vagrant VMs ===" -ForegroundColor Cyan
    foreach ($vm in $ClusterVMs) {
        vagrant status $vm
    }

    Write-Host ""
    Write-Host "=== Jenkins VM (informational only) ===" -ForegroundColor Cyan
    vagrant status jenkins

    $masterState = "unknown"
    $lines = & vagrant status k3s-master --machine-readable 2>$null
    foreach ($line in $lines) {
        if ($line -match ',state,([^,]+)$') { $masterState = $Matches[1]; break }
    }

    if ($masterState -ne "running") {
        Write-Host ""
        Write-Host "k3s-master is not running, so Kubernetes API checks are skipped." -ForegroundColor Yellow
        Write-Host "Use .\scripts\run.ps1 or .\scripts\resume.ps1 for the cluster."
        return
    }

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
    Write-Host "  .\scripts\deployment-status.ps1 all"
    Write-Host "Jenkins detailed status:" -ForegroundColor DarkGray
    Write-Host "  .\scripts\jenkins-status.ps1"
}
finally {
    Pop-Location
}
