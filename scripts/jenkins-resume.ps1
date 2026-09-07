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

function Wait-JenkinsSsh {
    param(
        [int]$Attempts = 60,
        [int]$DelaySeconds = 5
    )

    for ($i = 1; $i -le $Attempts; $i++) {
        & vagrant ssh jenkins -c "true" *> $null
        if ($LASTEXITCODE -eq 0) { return }
        Start-Sleep -Seconds $DelaySeconds
    }

    throw "Jenkins VM is running but is not reachable by Vagrant SSH."
}

function Test-JenkinsService {
    & vagrant ssh jenkins -c "sudo systemctl is-active jenkins && curl -fsSI --max-time 5 http://127.0.0.1:8080/jenkins/login | head -1"
    if ($LASTEXITCODE -ne 0) {
        throw "Jenkins VM is reachable, but Jenkins service or /jenkins validation failed."
    }
}


Push-Location $RepoRoot
try {
    Write-Host "Resuming Jenkins VM only..." -ForegroundColor Cyan
    $state = Get-JenkinsVmState
    Write-Host "Jenkins state: $state" -ForegroundColor DarkGray

    switch ($state) {
        "running" {
            Write-Host "Jenkins is already running." -ForegroundColor DarkGray
        }
        "saved" {
            & vagrant resume jenkins
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0) {
                $after = Get-JenkinsVmState
                if ($after -ne "running") {
                    throw "Could not resume Jenkins (exit code $exitCode, state=$after)."
                }
                Write-Host "Vagrant reported a resume error, but Jenkins is running; continuing." -ForegroundColor Yellow
            }
        }
        "suspended" {
            & vagrant resume jenkins
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0) {
                $after = Get-JenkinsVmState
                if ($after -ne "running") {
                    throw "Could not resume Jenkins (exit code $exitCode, state=$after)."
                }
            }
        }
        "poweroff" {
            Write-Host "Jenkins is powered off; starting it without provisioning..." -ForegroundColor Cyan
            & vagrant up jenkins --no-provision
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0) {
                $after = Get-JenkinsVmState
                if ($after -ne "running") {
                    throw "Could not start Jenkins (exit code $exitCode, state=$after)."
                }
                Write-Host "Vagrant reported a boot error, but Jenkins is running; continuing." -ForegroundColor Yellow
            }
        }
        "not_created" {
            throw "Jenkins VM does not exist. Create/provision it first with .\scripts\jenkins-up.ps1."
        }
        default {
            throw "Cannot safely resume Jenkins from state '$state'."
        }
    }

    Wait-JenkinsSsh
    Test-JenkinsService

    Write-Host ""
    Write-Host "Jenkins VM is running." -ForegroundColor Green
    Write-Host "Direct backend: http://$($env:JENKINS_LAN_IP):8080/jenkins/"
    Write-Host "Kubernetes cluster VMs were not changed." -ForegroundColor DarkGray
}
finally {
    Pop-Location
}
