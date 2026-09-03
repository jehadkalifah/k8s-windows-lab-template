param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet("all","argocd","cert-manager","istio","longhorn","monitoring","vault","velero")]
    [string]$Component
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot\load-config.ps1"

function Invoke-Stage2Component {
    param([string]$Name)

    Write-Host ""
    Write-Host "----------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " Deploying: $Name" -ForegroundColor Cyan
    Write-Host "----------------------------------------------------" -ForegroundColor DarkCyan

    switch ($Name) {
        "cert-manager" {
            vagrant ssh k3s-master -c "sudo bash /vagrant/deployments/cert-manager/install.sh"
        }
        "longhorn" {
            vagrant ssh k3s-master -c "sudo bash /vagrant/deployments/longhorn/install.sh"
        }
        "vault" {
            vagrant ssh k3s-master -c "sudo bash /vagrant/deployments/vault/install.sh"
        }
        "monitoring" {
            vagrant ssh k3s-master -c "sudo bash /vagrant/deployments/monitoring/install.sh"
        }
        "argocd" {
            vagrant ssh k3s-master -c "sudo bash /vagrant/deployments/argocd/install.sh"
        }
        "istio" {
            $remote = "sudo env METALLB_POOL_START='$env:METALLB_POOL_START' METALLB_POOL_END='$env:METALLB_POOL_END' bash /vagrant/deployments/istio/install.sh"
            vagrant ssh k3s-master -c $remote
        }
        "velero" {
            vagrant ssh k3s-master -c "sudo bash /vagrant/deployments/velero/install.sh"
        }
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Stage 2 deployment failed for '$Name'."
    }

    # Reconcile browser publishing through the shared Istio Gateway.
    if ($Name -eq "istio") {
        & "$PSScriptRoot\publish.ps1" all
    }
    elseif ($Name -in @("longhorn","vault","monitoring","argocd","velero")) {
        & "$PSScriptRoot\publish.ps1" $Name
    }
}

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

    if ($Component -eq "all") {
        # Authoritative Stage 2 order:
        # 1. cert-manager
        # 2. Longhorn
        # 3. HashiCorp Vault
        # 4. Monitoring
        # 5. Argo CD
        # 6. Istio + Gateway API + MetalLB
        # 7. Velero + MinIO
        #
        # Browser-facing components installed before Istio are reconciled by
        # publish.ps1 all immediately after the shared Gateway is installed.
        foreach ($item in @("cert-manager","longhorn","vault","monitoring","argocd","istio","velero")) {
            Invoke-Stage2Component $item
        }
    }
    else {
        Invoke-Stage2Component $Component
    }

    Write-Host ""
    Write-Host "Stage 2 deployment completed." -ForegroundColor Green
    Write-Host "Status:"
    Write-Host "  .\scripts\deployment-status.ps1 $Component"
}
finally {
    Pop-Location
}
