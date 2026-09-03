param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet("cert-manager","istio")]
    [string]$Component
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot\load-config.ps1"

Push-Location $RepoRoot
try {
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host " STAGE 2 - DEPLOY: $($Component.ToUpper())" -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "Validating base cluster..." -ForegroundColor Cyan
    vagrant ssh k3s-master -c "sudo kubectl wait --for=condition=Ready nodes --all --timeout=120s"
    if ($LASTEXITCODE -ne 0) {
        throw "Base Kubernetes cluster is not Ready."
    }

    switch ($Component) {
        "cert-manager" {
            Write-Host "cert-manager: v1.21.1"
            Write-Host ""
            vagrant ssh k3s-master -c "sudo bash /vagrant/deployments/cert-manager/install.sh"
            if ($LASTEXITCODE -ne 0) {
                throw "cert-manager deployment failed."
            }
        }

        "istio" {
            Write-Host "Gateway API: v1.6.0"
            Write-Host "MetalLB:     v0.16.1"
            Write-Host "Istio:       1.31.0"
            Write-Host "MetalLB IPs: $env:METALLB_POOL_START - $env:METALLB_POOL_END"
            Write-Host ""

            $remote = "sudo env METALLB_POOL_START='$env:METALLB_POOL_START' METALLB_POOL_END='$env:METALLB_POOL_END' bash /vagrant/deployments/istio/install.sh"
            vagrant ssh k3s-master -c $remote
            if ($LASTEXITCODE -ne 0) {
                throw "Istio deployment failed."
            }
        }
    }

    Write-Host ""
    Write-Host "Stage 2 '$Component' deployment completed." -ForegroundColor Green
    Write-Host "Status:"
    Write-Host "  .\scripts\deployment-status.ps1 $Component"
}
finally {
    Pop-Location
}
