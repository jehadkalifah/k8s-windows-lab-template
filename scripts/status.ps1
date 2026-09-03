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
    Write-Host "=== Platform pods ===" -ForegroundColor Cyan
    vagrant ssh k3s-master -c "sudo kubectl get pods -A"

    Write-Host ""
    Write-Host "=== LoadBalancer services ===" -ForegroundColor Cyan
    vagrant ssh k3s-master -c "sudo kubectl get svc -A"
}
finally {
    Pop-Location
}
