param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet("create","list","restore","delete","describe")]
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
    if ($Name -notmatch '^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$') {
        throw "Velero backup names must use lowercase letters, numbers, dot and hyphen."
    }
}

function Invoke-Master {
    param([Parameter(Mandatory=$true)][string]$Command)
    & vagrant ssh k3s-master -c $Command
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed on k3s-master: $Command"
    }
}

function Get-BackupPhase {
    param([string]$BackupName)
    $output = & vagrant ssh k3s-master -c "sudo kubectl -n velero get backup $BackupName -o jsonpath='{.status.phase}'" 2>$null
    if ($LASTEXITCODE -ne 0) { return "" }
    return (($output | Select-Object -Last 1) -as [string]).Trim()
}

Push-Location $RepoRoot
try {
    if ($Action -ne "list") {
        Require-Name
    }

    # Every Velero operation must target the K3s cluster only. Jenkins is never
    # started by these commands.
    Ensure-ClusterReady -TimeoutSeconds 600
    Assert-VeleroReady

    switch ($Action) {
        "create" {
            $existing = Get-BackupPhase -BackupName $Name
            if (-not [string]::IsNullOrWhiteSpace($existing)) {
                throw "Velero backup '$Name' already exists (phase: $existing). Delete it first or choose another name."
            }

            Write-Host "Creating Velero backup '$Name'..." -ForegroundColor Cyan
            Invoke-Master -Command "velero backup create $Name --include-cluster-scoped-resources=true --exclude-namespaces velero --default-volumes-to-fs-backup --wait"

            $phase = Get-BackupPhase -BackupName $Name
            if ($phase -ne "Completed") {
                Invoke-Master -Command "velero backup describe $Name --details"
                throw "Velero backup '$Name' finished with phase '$phase' instead of 'Completed'."
            }

            Invoke-Master -Command "velero backup describe $Name --details"
            Write-Host "Velero backup '$Name' completed successfully." -ForegroundColor Green
        }

        "list" {
            Invoke-Master -Command "velero backup get"
        }

        "describe" {
            Invoke-Master -Command "velero backup describe $Name --details"
        }

        "restore" {
            $phase = Get-BackupPhase -BackupName $Name
            if ($phase -ne "Completed") {
                throw "Velero backup '$Name' is not restorable because its phase is '$phase'. Expected 'Completed'."
            }

            $RestoreName = "$Name-restore-$(Get-Date -Format 'yyyyMMddHHmmss')"
            Write-Host "Restoring Velero backup '$Name' as '$RestoreName'..." -ForegroundColor Cyan
            Invoke-Master -Command "velero restore create $RestoreName --from-backup $Name --wait"
            Invoke-Master -Command "velero restore describe $RestoreName --details"
            Write-Host "Velero restore '$RestoreName' completed." -ForegroundColor Green
        }

        "delete" {
            $phase = Get-BackupPhase -BackupName $Name
            if ([string]::IsNullOrWhiteSpace($phase)) {
                Write-Host "Velero backup '$Name' does not exist; nothing to delete." -ForegroundColor DarkGray
                return
            }

            Write-Host "Deleting Velero backup '$Name'..." -ForegroundColor Yellow
            Invoke-Master -Command "velero backup delete $Name --confirm"

            $deadline = (Get-Date).AddMinutes(5)
            do {
                Start-Sleep -Seconds 3
                $stillThere = Get-BackupPhase -BackupName $Name
                if ([string]::IsNullOrWhiteSpace($stillThere)) { break }
            } while ((Get-Date) -lt $deadline)

            if (-not [string]::IsNullOrWhiteSpace((Get-BackupPhase -BackupName $Name))) {
                throw "Timed out waiting for Velero backup '$Name' to be deleted."
            }

            Write-Host "Velero backup '$Name' deleted." -ForegroundColor Green
        }
    }
}
finally {
    Pop-Location
}
