$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$VMs = @("k3s-master", "k3s-worker1", "k3s-worker2")

. "$PSScriptRoot\find-vboxmanage.ps1"
$VBoxManage = Get-VBoxManagePath

function Invoke-VBoxManage {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Arguments,
        [switch]$IgnoreFailure
    )

    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()

    try {
        $process = Start-Process `
            -FilePath $VBoxManage `
            -ArgumentList $Arguments `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -RedirectStandardOutput $stdoutFile `
            -RedirectStandardError $stderrFile

        $stdout = ""
        $stderr = ""

        if (Test-Path $stdoutFile) {
            $stdout = Get-Content $stdoutFile -Raw -ErrorAction SilentlyContinue
        }

        if (Test-Path $stderrFile) {
            $stderr = Get-Content $stderrFile -Raw -ErrorAction SilentlyContinue
        }

        if ($process.ExitCode -ne 0 -and -not $IgnoreFailure) {
            if (-not [string]::IsNullOrWhiteSpace($stderr)) {
                Write-Host $stderr.Trim() -ForegroundColor Red
            }
            throw "VBoxManage failed: $($Arguments -join ' ') (exit code $($process.ExitCode))."
        }

        return [PSCustomObject]@{
            ExitCode = $process.ExitCode
            StdOut   = $stdout
            StdErr   = $stderr
        }
    }
    finally {
        Remove-Item $stdoutFile -Force -ErrorAction SilentlyContinue
        Remove-Item $stderrFile -Force -ErrorAction SilentlyContinue
    }
}

function Get-VMState {
    param([string]$VMName)

    $result = Invoke-VBoxManage -Arguments @("showvminfo", $VMName, "--machinereadable") -IgnoreFailure

    if ($result.ExitCode -ne 0) {
        return $null
    }

    $match = [regex]::Match($result.StdOut, '(?m)^VMState="([^"]+)"$')
    if ($match.Success) {
        return $match.Groups[1].Value
    }

    return "unknown"
}

Push-Location $RepoRoot

try {
    Write-Host "This destroys all three VMs and their local cluster data." -ForegroundColor Yellow
    $confirmation = Read-Host "Type DESTROY to continue"

    if ($confirmation -ne "DESTROY") {
        Write-Host "Cancelled."
        exit 0
    }

    Write-Host ""
    Write-Host "Using VirtualBox directly; bridge configuration is not required." -ForegroundColor Cyan
    Write-Host "VBoxManage: $VBoxManage" -ForegroundColor DarkGray
    Write-Host ""

    foreach ($vm in $VMs) {
        $state = Get-VMState -VMName $vm

        if ($null -eq $state) {
            Write-Host "$vm is not registered in VirtualBox; skipping." -ForegroundColor DarkGray
            continue
        }

        Write-Host "$vm state: $state" -ForegroundColor Cyan

        if ($state -in @("running", "paused", "stuck", "teleporting", "live-snapshotting")) {
            Write-Host "Powering off $vm..." -ForegroundColor Cyan
            $poweroff = Invoke-VBoxManage -Arguments @("controlvm", $vm, "poweroff") -IgnoreFailure

            if ($poweroff.ExitCode -ne 0) {
                Write-Host "Power-off returned a non-zero exit code; continuing with deletion attempt." -ForegroundColor Yellow
            }
            else {
                Start-Sleep -Seconds 1
            }
        }

        Write-Host "Deleting $vm and its VirtualBox files..." -ForegroundColor Cyan
        Invoke-VBoxManage -Arguments @("unregistervm", $vm, "--delete") | Out-Null
        Write-Host "$vm deleted." -ForegroundColor Green
    }

    # Remove Vagrant's local machine IDs. This is essential when VMs were
    # deleted directly with VBoxManage, otherwise a later `vagrant up` may use
    # stale machine metadata.
    $vagrantState = Join-Path $RepoRoot ".vagrant"
    if (Test-Path $vagrantState) {
        Write-Host "Removing stale .vagrant metadata..." -ForegroundColor Cyan
        Remove-Item $vagrantState -Recurse -Force
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
    Write-Host "Kept: scripts\lab-config.ps1" -ForegroundColor Green
    Write-Host ""
    Write-Host "To rebuild:" -ForegroundColor Cyan
    Write-Host "  .\scripts\up.ps1"
}
finally {
    Pop-Location
}
