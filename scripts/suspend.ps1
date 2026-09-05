$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ClusterVMs = @("k3s-master", "k3s-worker1", "k3s-worker2")

Push-Location $RepoRoot
try {
    Write-Host "Suspending Kubernetes cluster VMs only..." -ForegroundColor Cyan
    Write-Host "Jenkins is intentionally excluded and its current state is unchanged." -ForegroundColor Yellow

    foreach ($vm in $ClusterVMs) {
        $lines = & vagrant status $vm --machine-readable 2>$null
        $state = "unknown"
        foreach ($line in $lines) {
            if ($line -match ',state,([^,]+)$') { $state = $Matches[1]; break }
        }

        switch ($state) {
            "running" {
                Write-Host "Suspending $vm..." -ForegroundColor Cyan
                & vagrant suspend $vm
                if ($LASTEXITCODE -ne 0) { throw "Failed to suspend $vm." }
            }
            "saved" { Write-Host "$vm is already suspended." -ForegroundColor DarkGray }
            "suspended" { Write-Host "$vm is already suspended." -ForegroundColor DarkGray }
            "poweroff" { Write-Host "$vm is powered off; leaving it off." -ForegroundColor DarkGray }
            "not_created" { Write-Host "$vm does not exist; skipping." -ForegroundColor DarkGray }
            default { throw "Cannot safely suspend $vm from state '$state'." }
        }
    }

    Write-Host ""
    Write-Host "Kubernetes cluster VMs suspended successfully." -ForegroundColor Green
    Write-Host "Jenkins was not changed." -ForegroundColor DarkGray
    Write-Host "Resume cluster with: .\scripts\resume.ps1"
}
finally {
    Pop-Location
}
