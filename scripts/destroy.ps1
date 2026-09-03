$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $RepoRoot

try {
    Write-Host "This destroys all three VMs and their local cluster data." -ForegroundColor Yellow
    $confirmation = Read-Host "Type DESTROY to continue"

    if ($confirmation -ne "DESTROY") {
        Write-Host "Cancelled."
        exit 0
    }

    Write-Host "Destroying Kubernetes lab VMs..." -ForegroundColor Cyan

    # Do NOT load lab-config.ps1 here.
    # The Vagrantfile now allows destroy/snapshot operations without a bridge
    # variable. Bridge configuration is only required when creating the lab.
    vagrant destroy -f

    if ($LASTEXITCODE -ne 0) {
        throw "vagrant destroy failed with exit code $LASTEXITCODE."
    }

    $kubeDir = Join-Path $RepoRoot ".kube"
    if (Test-Path $kubeDir) {
        Remove-Item $kubeDir -Recurse -Force
    }

    $tokenFile = Join-Path $RepoRoot ".k3s-token"
    if (Test-Path $tokenFile) {
        Remove-Item $tokenFile -Force
    }

    Write-Host ""
    Write-Host "Kubernetes lab destroyed successfully." -ForegroundColor Green
    Write-Host "scripts\\lab-config.ps1 was not removed."
}
finally {
    Pop-Location
}
