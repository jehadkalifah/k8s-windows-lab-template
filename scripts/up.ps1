$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot\load-config.ps1"

Push-Location $RepoRoot
try {
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host " STAGE 1 - CREATE K3S CLUSTER" -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Bridge:       $env:K8S_BRIDGE_ADAPTER"
    Write-Host "Master LAN:   $env:K3S_MASTER_LAN_IP"
    Write-Host "Worker 1 LAN: $env:K3S_WORKER1_LAN_IP"
    Write-Host "Worker 2 LAN: $env:K3S_WORKER2_LAN_IP"
    Write-Host "API LAN:      https://$($env:K3S_API_LAN_IP):6443"
    Write-Host "Flannel:      $env:K3S_FLANNEL_IFACE (192.168.56.0/24)"
    Write-Host ""
    Write-Host "Stage 1 creates only the base K3s cluster." -ForegroundColor Yellow
    Write-Host "All platform/application deployments are Stage 2." -ForegroundColor Yellow
    Write-Host ""

    Write-Host "[1/6] Creating/provisioning k3s-master..." -ForegroundColor Cyan
    vagrant up k3s-master
    if ($LASTEXITCODE -ne 0) { throw "Failed to create/start k3s-master." }

    Write-Host "[2/6] Creating/provisioning k3s-worker1..." -ForegroundColor Cyan
    vagrant up k3s-worker1
    if ($LASTEXITCODE -ne 0) { throw "Failed to create/start k3s-worker1." }

    Write-Host "[3/6] Creating/provisioning k3s-worker2..." -ForegroundColor Cyan
    vagrant up k3s-worker2
    if ($LASTEXITCODE -ne 0) { throw "Failed to create/start k3s-worker2." }

    Write-Host "[4/6] Waiting for all 3 Kubernetes nodes to become Ready..." -ForegroundColor Cyan
    vagrant ssh k3s-master -c "sudo kubectl wait --for=condition=Ready nodes --all --timeout=300s"
    if ($LASTEXITCODE -ne 0) { throw "Kubernetes nodes did not become Ready." }

    $nodeCountOutput = vagrant ssh k3s-master -c "sudo kubectl get nodes --no-headers | wc -l"
    $nodeCount = (($nodeCountOutput | Select-Object -Last 1) -as [string]).Trim()
    if ($nodeCount -ne "3") { throw "Expected 3 Kubernetes nodes, found $nodeCount." }

    Write-Host "[5/6] Verifying Flannel uses the host-only inter-node interface..." -ForegroundColor Cyan
    & "$PSScriptRoot\check-flannel.ps1"

    Write-Host "[6/6] Generating local and remote kubeconfigs..." -ForegroundColor Cyan
    & "$PSScriptRoot\get-kubeconfig.ps1"

    Write-Host ""
    Write-Host "Stage 1 complete: K3s cluster is ready." -ForegroundColor Green
    & "$PSScriptRoot\status.ps1"

    Write-Host ""
    Write-Host "NEXT:" -ForegroundColor Yellow
    Write-Host "  .\scripts\deploy.ps1 istio"
}
finally {
    Pop-Location
}
