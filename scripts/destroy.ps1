$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$VMs = @("k3s-master", "k3s-worker1", "k3s-worker2")

. "$PSScriptRoot\find-vboxmanage.ps1"
$VBoxManage = Get-VBoxManagePath

function Invoke-VBox {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Arguments,
        [switch]$IgnoreFailure
    )

    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()

    try {
        $p = Start-Process -FilePath $VBoxManage `
            -ArgumentList $Arguments `
            -Wait -PassThru -NoNewWindow `
            -RedirectStandardOutput $outFile `
            -RedirectStandardError $errFile

        $stdout = if (Test-Path $outFile) { Get-Content $outFile -Raw -ErrorAction SilentlyContinue } else { "" }
        $stderr = if (Test-Path $errFile) { Get-Content $errFile -Raw -ErrorAction SilentlyContinue } else { "" }

        if ($p.ExitCode -ne 0 -and -not $IgnoreFailure) {
            if ($stderr) { Write-Host $stderr.Trim() -ForegroundColor Red }
            throw "VBoxManage failed: $($Arguments -join ' ') (exit code $($p.ExitCode))."
        }

        [PSCustomObject]@{
            ExitCode = $p.ExitCode
            StdOut   = $stdout
            StdErr   = $stderr
        }
    }
    finally {
        Remove-Item $outFile,$errFile -Force -ErrorAction SilentlyContinue
    }
}

function Get-VMState {
    param([string]$VMName)

    $info = Invoke-VBox -Arguments @("showvminfo", $VMName, "--machinereadable") -IgnoreFailure
    if ($info.ExitCode -ne 0) {
        return $null
    }

    # Handles both LF and CRLF output.
    $m = [regex]::Match($info.StdOut, '(?m)^VMState="([^"]+)"\r?$')
    if ($m.Success) {
        return $m.Groups[1].Value
    }

    return "unknown"
}

function Wait-For-UnlockedVM {
    param([string]$VMName)

    for ($i = 0; $i -lt 10; $i++) {
        $info = Invoke-VBox -Arguments @("showvminfo", $VMName, "--machinereadable") -IgnoreFailure

        if ($info.ExitCode -ne 0) {
            return
        }

        if ($info.StdOut -notmatch '(?m)^VMState="running"\r?$' -and
            $info.StdOut -notmatch '(?m)^VMState="paused"\r?$' -and
            $info.StdOut -notmatch '(?m)^VMState="stuck"\r?$') {
            Start-Sleep -Seconds 1
            return
        }

        Start-Sleep -Seconds 1
    }
}

function Remove-VM {
    param([string]$VMName)

    $state = Get-VMState -VMName $VMName

    if ($null -eq $state) {
        Write-Host "$VMName is not registered; skipping." -ForegroundColor DarkGray
        return
    }

    Write-Host "$VMName state: $state" -ForegroundColor Cyan

    if ($state -in @("running","paused","stuck","teleporting","live-snapshotting")) {
        Write-Host "Powering off $VMName..." -ForegroundColor Cyan
        Invoke-VBox -Arguments @("controlvm", $VMName, "poweroff") -IgnoreFailure | Out-Null
        Wait-For-UnlockedVM -VMName $VMName
    }
    elseif ($state -eq "saved") {
        Write-Host "Discarding saved state for $VMName..." -ForegroundColor Cyan
        Invoke-VBox -Arguments @("discardstate", $VMName) -IgnoreFailure | Out-Null
        Start-Sleep -Seconds 1
    }

    for ($attempt = 1; $attempt -le 5; $attempt++) {
        Write-Host "Deleting $VMName (attempt $attempt/5)..." -ForegroundColor Cyan
        $delete = Invoke-VBox -Arguments @("unregistervm", $VMName, "--delete") -IgnoreFailure

        if ($delete.ExitCode -eq 0) {
            Write-Host "$VMName deleted." -ForegroundColor Green
            return
        }

        if ($delete.StdErr -match 'locked') {
            Write-Host "$VMName is still locked; waiting before retry..." -ForegroundColor Yellow
            Start-Sleep -Seconds 2
            continue
        }

        throw "Failed to delete $VMName. $($delete.StdErr)"
    }

    throw "Could not delete $VMName because VirtualBox kept it locked after multiple retries."
}

Push-Location $RepoRoot
try {
    Write-Host "This permanently destroys all three lab VMs and local cluster data." -ForegroundColor Yellow
    $confirmation = Read-Host "Type DESTROY to continue"

    if ($confirmation -ne "DESTROY") {
        Write-Host "Cancelled."
        exit 0
    }

    Write-Host ""
    Write-Host "Using VBoxManage directly; bridge variables are not required." -ForegroundColor Cyan
    Write-Host "VBoxManage: $VBoxManage" -ForegroundColor DarkGray
    Write-Host ""

    foreach ($vm in $VMs) {
        Remove-VM -VMName $vm
    }

    foreach ($path in @(".vagrant", ".kube", ".k3s-token")) {
        $full = Join-Path $RepoRoot $path
        if (Test-Path $full) {
            Remove-Item $full -Recurse -Force -ErrorAction Stop
        }
    }

    Write-Host ""
    Write-Host "Kubernetes lab destroyed successfully." -ForegroundColor Green
    Write-Host "Kept: scripts\lab-config.ps1" -ForegroundColor Green
}
finally {
    Pop-Location
}
