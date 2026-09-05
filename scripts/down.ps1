$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ClusterVMs = @("k3s-master", "k3s-worker1", "k3s-worker2")

. "$PSScriptRoot\load-config.ps1"

Push-Location $RepoRoot
try {
    Write-Host "Gracefully shutting down Kubernetes cluster VMs only..." -ForegroundColor Cyan
    Write-Host "Jenkins is intentionally excluded and its current state is unchanged." -ForegroundColor Yellow

    foreach ($vm in $ClusterVMs) {
        $lines = & vagrant status $vm --machine-readable 2>$null
        $state = "unknown"
        foreach ($line in $lines) {
            if ($line -match ',state,([^,]+)$') { $state = $Matches[1]; break }
        }

        switch ($state) {
            "running" {
                Write-Host "Halting $vm..." -ForegroundColor Cyan
                & vagrant halt $vm
                if ($LASTEXITCODE -ne 0) { throw "Failed to halt $vm." }
            }
            "saved" {
                Write-Host "$vm is suspended; leaving its saved state intact." -ForegroundColor DarkGray
            }
            "suspended" {
                Write-Host "$vm is suspended; leaving its saved state intact." -ForegroundColor DarkGray
            }
            "poweroff" { Write-Host "$vm is already powered off." -ForegroundColor DarkGray }
            "not_created" { Write-Host "$vm does not exist; skipping." -ForegroundColor DarkGray }
            default { throw "Cannot safely halt $vm from state '$state'." }
        }
    }

    Write-Host ""
    Write-Host "Kubernetes cluster VMs are powered off/safely preserved." -ForegroundColor Green
    Write-Host "Jenkins was not changed." -ForegroundColor DarkGray
    Write-Host "Start cluster again with: .\scripts\run.ps1"
}
finally {
    Pop-Location
}
