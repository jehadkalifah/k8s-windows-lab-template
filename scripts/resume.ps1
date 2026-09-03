$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot

# Keep Vagrant's networking model consistent with the original build.
. "$PSScriptRoot\load-config.ps1"

Push-Location $RepoRoot

try {
    Write-Host "Resuming suspended Kubernetes lab..." -ForegroundColor Cyan

    vagrant resume

    if ($LASTEXITCODE -ne 0) {
        throw "vagrant resume failed with exit code $LASTEXITCODE."
    }

    Write-Host ""
    Write-Host "Lab resumed successfully." -ForegroundColor Green

    & "$PSScriptRoot\get-kubeconfig.ps1"

    Write-Host ""
    Write-Host "Node status:" -ForegroundColor Cyan
    vagrant ssh k3s-master -c "sudo kubectl get nodes -o wide"
}
finally {
    Pop-Location
}
