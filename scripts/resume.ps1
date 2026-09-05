$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ClusterVMs = @("k3s-master", "k3s-worker1", "k3s-worker2")

. "$PSScriptRoot\load-config.ps1"

function Get-VagrantVmState {
    param([Parameter(Mandatory=$true)][string]$Name)

    $lines = & vagrant status $Name --machine-readable 2>$null
    if ($LASTEXITCODE -ne 0) { return "unknown" }

    foreach ($line in $lines) {
        if ($line -match ',state,([^,]+)$') {
            return $Matches[1]
        }
    }

    return "unknown"
}

function Wait-VagrantSsh {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [int]$Attempts = 60,
        [int]$DelaySeconds = 5
    )

    for ($i = 1; $i -le $Attempts; $i++) {
        & vagrant ssh $Name -c "true" *> $null
        if ($LASTEXITCODE -eq 0) { return }
        Start-Sleep -Seconds $DelaySeconds
    }

    throw "$Name is not reachable by Vagrant SSH."
}

function Start-ClusterVm {
    param([Parameter(Mandatory=$true)][string]$Name)

    $state = Get-VagrantVmState -Name $Name
    Write-Host "$Name state: $state" -ForegroundColor DarkGray

    switch ($state) {
        "running" {
            Write-Host "$Name is already running." -ForegroundColor DarkGray
        }
        "saved" {
            Write-Host "Resuming $Name..." -ForegroundColor Cyan
            & vagrant resume $Name
            $resumeExit = $LASTEXITCODE
            if ($resumeExit -ne 0) {
                $after = Get-VagrantVmState -Name $Name
                if ($after -ne "running") {
                    throw "Could not resume $Name (exit code $resumeExit, state=$after)."
                }
                Write-Host "$Name reported a resume error but is actually running; continuing." -ForegroundColor Yellow
            }
        }
        "suspended" {
            Write-Host "Resuming $Name..." -ForegroundColor Cyan
            & vagrant resume $Name
            $resumeExit = $LASTEXITCODE
            if ($resumeExit -ne 0) {
                $after = Get-VagrantVmState -Name $Name
                if ($after -ne "running") {
                    throw "Could not resume $Name (exit code $resumeExit, state=$after)."
                }
            }
        }
        "poweroff" {
            Write-Host "Starting powered-off $Name without provisioning..." -ForegroundColor Cyan
            & vagrant up $Name --no-provision
            $upExit = $LASTEXITCODE
            if ($upExit -ne 0) {
                $after = Get-VagrantVmState -Name $Name
                if ($after -ne "running") {
                    throw "Could not start $Name (exit code $upExit, state=$after)."
                }
                Write-Host "$Name reported a boot error but is actually running; continuing." -ForegroundColor Yellow
            }
        }
        "not_created" {
            throw "$Name does not exist. Use .\scripts\up.ps1 to create the K3s cluster."
        }
        default {
            Write-Host "Starting $Name without provisioning from state '$state'..." -ForegroundColor Cyan
            & vagrant up $Name --no-provision
            $upExit = $LASTEXITCODE
            if ($upExit -ne 0) {
                $after = Get-VagrantVmState -Name $Name
                if ($after -ne "running") {
                    throw "Could not start $Name (exit code $upExit, state=$after)."
                }
            }
        }
    }

    Wait-VagrantSsh -Name $Name
}

Push-Location $RepoRoot
try {
    Write-Host "Resuming/starting Kubernetes cluster VMs only..." -ForegroundColor Cyan
    Write-Host "Jenkins is intentionally excluded from this lifecycle command." -ForegroundColor Yellow
    Write-Host ""

    foreach ($vm in $ClusterVMs) {
        Start-ClusterVm -Name $vm
    }

    Write-Host ""
    Write-Host "Waiting for all 3 Kubernetes nodes to become Ready..." -ForegroundColor Cyan
    & vagrant ssh k3s-master -c "sudo kubectl wait --for=condition=Ready nodes --all --timeout=300s"
    if ($LASTEXITCODE -ne 0) {
        throw "Kubernetes nodes did not become Ready."
    }

    & "$PSScriptRoot\get-kubeconfig.ps1"

    Write-Host ""
    Write-Host "Node status:" -ForegroundColor Cyan
    & vagrant ssh k3s-master -c "sudo kubectl get nodes -o wide"

    Write-Host ""
    Write-Host "Kubernetes cluster is running." -ForegroundColor Green
    Write-Host "Jenkins was not started/resumed." -ForegroundColor DarkGray
    Write-Host "Start Jenkins separately with: .\scripts\jenkins-up.ps1" -ForegroundColor DarkGray
}
finally {
    Pop-Location
}
