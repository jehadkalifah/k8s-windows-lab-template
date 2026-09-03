param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet("all","argocd","cert-manager","istio","longhorn","monitoring","velero")]
    [string]$Component
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

function Show-Stage2Status {
    param([string]$Name)

    Write-Host ""
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host " STATUS: $($Name.ToUpper())" -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan

    vagrant ssh k3s-master -c "sudo bash /vagrant/deployments/$Name/status.sh"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Status check failed for '$Name'." -ForegroundColor Red
    }
}

Push-Location $RepoRoot
try {
    if ($Component -eq "all") {
        Write-Host ""
        Write-Host "Complete Stage 2 status order:" -ForegroundColor Yellow
        Write-Host "  1. cert-manager"
        Write-Host "  2. Longhorn"
        Write-Host "  3. Monitoring"
        Write-Host "  4. Argo CD"
        Write-Host "  5. Istio + Gateway API + MetalLB"
        Write-Host "  6. Velero + MinIO"
        Write-Host "  7. Shared Gateway publishing / HTTPRoutes"

        foreach ($item in @("cert-manager","longhorn","monitoring","argocd","istio","velero")) {
            Show-Stage2Status $item
        }

        Write-Host ""
        Write-Host "====================================================" -ForegroundColor Cyan
        Write-Host " STATUS: SHARED GATEWAY PUBLISHING" -ForegroundColor Cyan
        Write-Host "====================================================" -ForegroundColor Cyan
        & "$PSScriptRoot\publishing-status.ps1"

        Write-Host ""
        Write-Host "====================================================" -ForegroundColor Green
        Write-Host " COMPLETE STAGE 2 STATUS FINISHED" -ForegroundColor Green
        Write-Host "====================================================" -ForegroundColor Green
    }
    else {
        Show-Stage2Status $Component
    }
}
finally {
    Pop-Location
}
