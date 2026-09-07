$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot\load-config.ps1"


function Get-JenkinsVmState {
    $lines = & vagrant status jenkins --machine-readable 2>$null
    if ($LASTEXITCODE -ne 0) { return "unknown" }

    foreach ($line in $lines) {
        if ($line -match ',state,([^,]+)$') {
            return $Matches[1]
        }
    }

    return "unknown"
}



Push-Location $RepoRoot
try {
    Write-Host "Suspending Jenkins VM only..." -ForegroundColor Cyan
    $state = Get-JenkinsVmState
    Write-Host "Jenkins state: $state" -ForegroundColor DarkGray

    switch ($state) {
        "running" {
            & vagrant suspend jenkins
            if ($LASTEXITCODE -ne 0) { throw "Failed to suspend Jenkins VM." }
        }
        "saved" { Write-Host "Jenkins is already suspended." -ForegroundColor DarkGray }
        "suspended" { Write-Host "Jenkins is already suspended." -ForegroundColor DarkGray }
        "poweroff" { Write-Host "Jenkins is powered off; leaving it powered off." -ForegroundColor DarkGray }
        "not_created" { throw "Jenkins VM does not exist. Use .\scripts\jenkins-up.ps1 first." }
        default { throw "Cannot safely suspend Jenkins from state '$state'." }
    }

    $finalState = Get-JenkinsVmState
    Write-Host ""
    Write-Host "Jenkins final state: $finalState" -ForegroundColor Green
    Write-Host "Kubernetes cluster VMs were not changed." -ForegroundColor DarkGray
}
finally {
    Pop-Location
}
