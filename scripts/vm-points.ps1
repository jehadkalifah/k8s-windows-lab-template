param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet("create","list","restore","delete")]
    [string]$Action,

    [Parameter(Mandatory=$false, Position=1)]
    [string]$Name
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot\restore-common.ps1"

function Require-Name {
    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "A restore point name is required for action '$Action'."
    }
    if ($Name -notmatch '^[a-zA-Z0-9._-]+$') {
        throw "Use only letters, numbers, dot, underscore and hyphen in VM restore point names."
    }
}

function Test-SnapshotExists {
    param([string]$VM, [string]$SnapshotName)
    $output = & vagrant snapshot list $VM 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }
    foreach ($line in $output) {
        if ((($line -as [string]).Trim()) -eq $SnapshotName) { return $true }
    }
    return $false
}

function Assert-SnapshotExists {
    param([string]$VM, [string]$SnapshotName)
    if (-not (Test-SnapshotExists -VM $VM -SnapshotName $SnapshotName)) {
        throw "Snapshot '$SnapshotName' does not exist on $VM."
    }
}

Push-Location $RepoRoot
try {
    switch ($Action) {
        "create" {
            Require-Name

            foreach ($vm in $ClusterVMs) {
                if (Test-SnapshotExists -VM $vm -SnapshotName $Name) {
                    throw "Snapshot '$Name' already exists on $vm. Delete it first or choose another name."
                }
            }

            $snapshotError = $null
            Write-Host "Stopping all lab VMs before cluster snapshots..." -ForegroundColor Cyan
            Write-Host "Jenkins will be stopped but will NOT be snapshotted or restarted." -ForegroundColor Yellow
            Stop-AllLabVMsForRestorePoint

            try {
                foreach ($vm in $ClusterVMs) {
                    Write-Host "Creating VM snapshot '$Name' for $vm..." -ForegroundColor Cyan
                    & vagrant snapshot save $vm $Name
                    if ($LASTEXITCODE -ne 0) {
                        throw "Snapshot creation failed for $vm."
                    }
                }
            }
            catch {
                $snapshotError = $_
            }
            finally {
                Write-Host "Starting only the three K3s VMs after snapshot attempt..." -ForegroundColor Cyan
                Start-ClusterVMs -WaitForKubernetes -TimeoutSeconds 600
            }

            if ($null -ne $snapshotError) {
                throw $snapshotError
            }

            Write-Host "VM restore point '$Name' created for the three K3s nodes." -ForegroundColor Green
            Write-Host "Jenkins remains stopped by design." -ForegroundColor Yellow
        }

        "list" {
            foreach ($vm in $ClusterVMs) {
                Write-Host ""
                Write-Host "=== $vm ===" -ForegroundColor Cyan
                & vagrant snapshot list $vm
            }
            Write-Host ""
            Write-Host "Jenkins is intentionally excluded from VM restore points." -ForegroundColor DarkGray
        }

        "restore" {
            Require-Name

            foreach ($vm in $ClusterVMs) {
                Assert-SnapshotExists -VM $vm -SnapshotName $Name
            }

            Write-Host "Stopping all lab VMs before VM restore..." -ForegroundColor Cyan
            Write-Host "Jenkins will remain stopped after the restore." -ForegroundColor Yellow
            Stop-AllLabVMsForRestorePoint

            foreach ($vm in $ClusterVMs) {
                Write-Host "Restoring '$Name' on $vm..." -ForegroundColor Cyan
                & vagrant snapshot restore $vm $Name
                if ($LASTEXITCODE -ne 0) {
                    throw "Snapshot restore failed for $vm."
                }
            }

            Write-Host "Starting only the restored K3s VMs..." -ForegroundColor Cyan
            Start-ClusterVMs -WaitForKubernetes -TimeoutSeconds 600

            & "$PSScriptRoot\get-kubeconfig.ps1"
            & "$PSScriptRoot\status.ps1"

            Write-Host "VM restore point '$Name' restored." -ForegroundColor Green
            Write-Host "Jenkins remains stopped by design." -ForegroundColor Yellow
        }

        "delete" {
            Require-Name

            $deleted = 0
            foreach ($vm in $ClusterVMs) {
                if (-not (Test-SnapshotExists -VM $vm -SnapshotName $Name)) {
                    Write-Host "Snapshot '$Name' does not exist on $vm; skipping." -ForegroundColor DarkGray
                    continue
                }

                Write-Host "Deleting '$Name' from $vm..." -ForegroundColor Yellow
                & vagrant snapshot delete $vm $Name
                if ($LASTEXITCODE -ne 0) {
                    throw "Snapshot deletion failed for $vm."
                }
                $deleted++
            }

            if ($deleted -eq 0) {
                Write-Host "VM restore point '$Name' was not present on any K3s node." -ForegroundColor DarkGray
            }
            else {
                Write-Host "VM restore point '$Name' deleted from $deleted K3s node(s)." -ForegroundColor Green
            }
            Write-Host "Jenkins was not touched." -ForegroundColor DarkGray
        }
    }
}
finally {
    Pop-Location
}
