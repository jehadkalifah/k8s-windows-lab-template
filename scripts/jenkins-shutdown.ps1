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



function Wait-JenkinsSshForShutdown {
    for ($i = 1; $i -le 60; $i++) {
        & vagrant ssh jenkins -c "true" *> $null
        if ($LASTEXITCODE -eq 0) { return }
        Start-Sleep -Seconds 5
    }
    throw "Jenkins VM did not become reachable before shutdown."
}

Push-Location $RepoRoot
try {
    Write-Host "Shutting down Jenkins VM only..." -ForegroundColor Cyan
    $state = Get-JenkinsVmState
    Write-Host "Jenkins state: $state" -ForegroundColor DarkGray

    switch ($state) {
        "running" {
            & vagrant halt jenkins
            if ($LASTEXITCODE -ne 0) { throw "Failed to shut down Jenkins VM." }
        }
        "saved" {
            Write-Host "Jenkins is suspended; resuming it first so it can be cleanly shut down..." -ForegroundColor Cyan
            & vagrant resume jenkins
            $resumeExit = $LASTEXITCODE
            if ($resumeExit -ne 0) {
                $after = Get-JenkinsVmState
                if ($after -ne "running") {
                    throw "Could not resume Jenkins before shutdown (exit code $resumeExit, state=$after)."
                }
            }
            Wait-JenkinsSshForShutdown
            & vagrant halt jenkins
            if ($LASTEXITCODE -ne 0) { throw "Failed to shut down Jenkins VM after resume." }
        }
        "suspended" {
            Write-Host "Jenkins is suspended; resuming it first so it can be cleanly shut down..." -ForegroundColor Cyan
            & vagrant resume jenkins
            $resumeExit = $LASTEXITCODE
            if ($resumeExit -ne 0) {
                $after = Get-JenkinsVmState
                if ($after -ne "running") {
                    throw "Could not resume Jenkins before shutdown (exit code $resumeExit, state=$after)."
                }
            }
            Wait-JenkinsSshForShutdown
            & vagrant halt jenkins
            if ($LASTEXITCODE -ne 0) { throw "Failed to shut down Jenkins VM after resume." }
        }
        "poweroff" {
            Write-Host "Jenkins is already powered off." -ForegroundColor DarkGray
        }
        "not_created" { throw "Jenkins VM does not exist. Use .\scripts\jenkins-up.ps1 first." }
        default { throw "Cannot safely shut down Jenkins from state '$state'." }
    }

    $finalState = Get-JenkinsVmState
    Write-Host ""
    Write-Host "Jenkins final state: $finalState" -ForegroundColor Green
    Write-Host "Kubernetes cluster VMs were not changed." -ForegroundColor DarkGray
}
finally {
    Pop-Location
}
