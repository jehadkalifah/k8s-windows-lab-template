$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot

# Load the same bridge + MetalLB settings used when the lab was created.
. "$PSScriptRoot\load-config.ps1"

Push-Location $RepoRoot

try {
    Write-Host "Starting existing Kubernetes lab without provisioning..." -ForegroundColor Cyan

    vagrant up --no-provision

    if ($LASTEXITCODE -ne 0) {
        throw "vagrant up --no-provision failed with exit code $LASTEXITCODE."
    }

    Write-Host ""
    Write-Host "Kubernetes lab is running." -ForegroundColor Green
    & "$PSScriptRoot\get-kubeconfig.ps1"

    Write-Host ""
    Write-Host "Node status:" -ForegroundColor Cyan
    vagrant ssh k3s-master -c "sudo kubectl get nodes -o wide"
}
finally {
    Pop-Location
}
