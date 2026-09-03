$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot\load-config.ps1"

if ($env:K3S_FLANNEL_IFACE -ne "eth1") {
    Write-Host "WARNING: This lab is designed for Flannel on eth1." -ForegroundColor Yellow
    Write-Host "Configured value: $env:K3S_FLANNEL_IFACE" -ForegroundColor Yellow
}

function Set-FlannelConfig {
    param(
        [string]$Node,
        [string]$Service
    )

    Write-Host "Updating $Node..." -ForegroundColor Cyan

    $command = "sudo mkdir -p /etc/rancher/k3s; " +
               "sudo touch /etc/rancher/k3s/config.yaml; " +
               "sudo sed -i '/^[[:space:]]*flannel-iface:/d' /etc/rancher/k3s/config.yaml; " +
               "echo 'flannel-iface: $env:K3S_FLANNEL_IFACE' | sudo tee -a /etc/rancher/k3s/config.yaml >/dev/null; " +
               "sudo systemctl restart $Service"

    vagrant ssh $Node -c $command
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to update Flannel configuration on $Node."
    }
}

Push-Location $RepoRoot
try {
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host " REPAIR K3S FLANNEL UNDERLAY" -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Flannel interface: $env:K3S_FLANNEL_IFACE"
    Write-Host "K3s inter-node CIDR: 192.168.56.0/24"
    Write-Host ""

    # Restart agents first, then control plane.
    Set-FlannelConfig -Node "k3s-worker1" -Service "k3s-agent"
    Set-FlannelConfig -Node "k3s-worker2" -Service "k3s-agent"
    Set-FlannelConfig -Node "k3s-master"  -Service "k3s"

    Write-Host ""
    Write-Host "Waiting for all Kubernetes nodes..." -ForegroundColor Cyan
    vagrant ssh k3s-master -c "sudo kubectl wait --for=condition=Ready nodes --all --timeout=300s"
    if ($LASTEXITCODE -ne 0) {
        throw "Nodes did not return to Ready state."
    }

    Write-Host ""
    & "$PSScriptRoot\check-flannel.ps1"

    Write-Host ""
    Write-Host "Restarting CoreDNS..." -ForegroundColor Cyan
    vagrant ssh k3s-master -c "sudo kubectl -n kube-system rollout restart deployment/coredns && sudo kubectl -n kube-system rollout status deployment/coredns --timeout=180s"
    if ($LASTEXITCODE -ne 0) {
        throw "CoreDNS did not become Ready."
    }

    Write-Host ""
    Write-Host "Checking whether Istio Gateway already exists..." -ForegroundColor Cyan
    vagrant ssh k3s-master -c "sudo kubectl -n istio-ingress get deployment public-gateway-istio >/dev/null 2>&1"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Restarting Istio Gateway after network repair..." -ForegroundColor Cyan
        vagrant ssh k3s-master -c "sudo kubectl -n istio-ingress rollout restart deployment/public-gateway-istio && sudo kubectl -n istio-ingress rollout status deployment/public-gateway-istio --timeout=180s"
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARNING: Istio Gateway is still not Ready. Check its logs." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "Istio Gateway is not installed yet; nothing to restart." -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "Flannel repair complete." -ForegroundColor Green
    Write-Host "Next checks:" -ForegroundColor Yellow
    Write-Host "  .\scripts\status.ps1"
    Write-Host "  .\scripts\deployment-status.ps1 istio"
}
finally {
    Pop-Location
}
