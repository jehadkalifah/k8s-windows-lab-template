param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet("all","argocd","cert-manager","harbor","istio","keycloak","kiali","longhorn","monitoring","reloader","vault","velero")]
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

        "reloader" {
            vagrant ssh k3s-master -c "sudo bash /vagrant/deployments/reloader/install.sh"
        }

        "istio" {
            $remote = "sudo env METALLB_POOL_START='$env:METALLB_POOL_START' METALLB_POOL_END='$env:METALLB_POOL_END' bash /vagrant/deployments/istio/install.sh"
            vagrant ssh k3s-master -c $remote
        }

        "kiali" {
            vagrant ssh k3s-master -c "sudo bash /vagrant/deployments/kiali/install.sh"
        }

        "keycloak" {
            vagrant ssh k3s-master -c "sudo bash /vagrant/deployments/keycloak/install.sh"
        }

        "harbor" {
            $gatewayNamespace = if ($env:K8S_GATEWAY_NAMESPACE) {
                $env:K8S_GATEWAY_NAMESPACE
            }
            else {
                "istio-ingress"
            }

            $gatewayName = if ($env:K8S_GATEWAY_NAME) {
                $env:K8S_GATEWAY_NAME
            }
            else {
                "public-gateway"
            }

            $harborHost = if ($env:HARBOR_PUBLISH_HOST) {
                $env:HARBOR_PUBLISH_HOST
            }
            else {
                ""
            }

            $remote = "sudo env GATEWAY_NAMESPACE='$gatewayNamespace' GATEWAY_NAME='$gatewayName' HARBOR_PUBLISH_HOST='$harborHost' bash /vagrant/deployments/harbor/install.sh"
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
    elseif ($Name -in @(
        "longhorn",
        "vault",
        "monitoring",
        "argocd",
        "kiali",
        "keycloak",
        "harbor",
        "velero"
    )) {
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
        #
        # 1.  cert-manager
        # 2.  Longhorn
        #     -> mandatory 20-minute initialization wait
        #     -> Longhorn deployment readiness verification
        # 3.  HashiCorp Vault
        # 4.  Monitoring
        # 5.  Argo CD
        # 6.  Stakater Reloader
        # 7.  Istio + Gateway API + MetalLB
        # 8.  Kiali Operator + Kiali
        # 9.  Keycloak Operator + PostgreSQL
        # 10. Harbor private registry
        # 11. Velero + MinIO
        #
        # Browser-facing components installed before Istio are reconciled by
        # publish.ps1 all immediately after the shared Gateway is installed.

        $Stage2Components = @(
            "cert-manager",
            "longhorn",
            "vault",
            "monitoring",
            "argocd",
            "reloader",
            "istio",
            "kiali",
            "keycloak",
            "harbor",
            "velero"
        )

        foreach ($item in $Stage2Components) {

            Invoke-Stage2Component $item

            # ------------------------------------------------------------
            # Longhorn initialization wait
            # ------------------------------------------------------------
            #
            # Longhorn can require additional time after Helm installation
            # while managers, drivers, CSI components and supporting pods
            # initialize across all K3s nodes.
            #
            # When deploying ALL Stage 2 components:
            #
            #   1. Longhorn is installed.
            #   2. Wait exactly 20 minutes.
            #   3. Verify Longhorn deployments are Available.
            #   4. Continue with Vault and the remaining components.
            #
            # This delay applies only to:
            #
            #   .\scripts\deploy.ps1 all
            #
            # It does NOT apply to:
            #
            #   .\scripts\deploy.ps1 longhorn
            #
            if ($item -eq "longhorn") {

                Write-Host ""
                Write-Host "====================================================" -ForegroundColor Yellow
                Write-Host " LONGHORN INITIALIZATION WAIT" -ForegroundColor Yellow
                Write-Host "====================================================" -ForegroundColor Yellow

                Write-Host ""
                Write-Host "Longhorn installation completed." -ForegroundColor Green
                Write-Host "Waiting 20 minutes for Longhorn to fully initialize..." -ForegroundColor Yellow
                Write-Host "Wait duration: 1200 seconds" -ForegroundColor DarkGray
                Write-Host ""

                Start-Sleep -Seconds 1200

                Write-Host ""
                Write-Host "20-minute Longhorn initialization wait completed." -ForegroundColor Green

                Write-Host ""
                Write-Host "Checking Longhorn deployment readiness..." -ForegroundColor Cyan

                vagrant ssh k3s-master -c "sudo kubectl -n longhorn-system wait --for=condition=Available deployment --all --timeout=300s"

                if ($LASTEXITCODE -ne 0) {

                    Write-Host ""
                    Write-Host "Longhorn deployments are not fully Ready." -ForegroundColor Red

                    Write-Host ""
                    Write-Host "Longhorn pods:" -ForegroundColor Yellow
                    vagrant ssh k3s-master -c "sudo kubectl -n longhorn-system get pods -o wide"

                    Write-Host ""
                    Write-Host "Longhorn deployments:" -ForegroundColor Yellow
                    vagrant ssh k3s-master -c "sudo kubectl -n longhorn-system get deployments"

                    Write-Host ""
                    Write-Host "Longhorn daemonsets:" -ForegroundColor Yellow
                    vagrant ssh k3s-master -c "sudo kubectl -n longhorn-system get daemonsets"

                    throw "Longhorn did not become Ready after the 20-minute initialization period and 5-minute readiness timeout."
                }

                Write-Host ""
                Write-Host "Longhorn deployment readiness check passed." -ForegroundColor Green

                Write-Host ""
                Write-Host "Current Longhorn pods:" -ForegroundColor Cyan
                vagrant ssh k3s-master -c "sudo kubectl -n longhorn-system get pods -o wide"

                if ($LASTEXITCODE -ne 0) {
                    throw "Unable to retrieve Longhorn pod status after readiness verification."
                }

                Write-Host ""
                Write-Host "Longhorn is Ready." -ForegroundColor Green
                Write-Host "Continuing Stage 2 deployment with Vault..." -ForegroundColor Green
                Write-Host ""
            }
        }
    }
    else {

        # Deploy only the requested component.
        #
        # The 20-minute Longhorn delay is intentionally NOT applied when
        # Longhorn is deployed individually.
        Invoke-Stage2Component $Component
    }

    Write-Host ""
    Write-Host "====================================================" -ForegroundColor Green
    Write-Host " STAGE 2 DEPLOYMENT COMPLETED" -ForegroundColor Green
    Write-Host "====================================================" -ForegroundColor Green

    Write-Host ""
    Write-Host "Status:" -ForegroundColor Cyan
    Write-Host "  .\scripts\deployment-status.ps1 $Component"
}
finally {
    Pop-Location
}