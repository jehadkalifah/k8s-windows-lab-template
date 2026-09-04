param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet("create","list","restore","delete")]
    [string]$Action,

    [Parameter(Mandatory=$false, Position=1)]
    [string]$Name,

    [Parameter(Mandatory=$false)]
    [ValidateSet("vm","cluster","both")]
    [string]$Level = "both"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

function Require-Name {
    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "A restore point name is required for action '$Action'."
    }
}

Push-Location $RepoRoot
try {
    if ($Action -eq "list") {
        Write-Host ""
        Write-Host "================ VM RESTORE POINTS ================" -ForegroundColor Cyan
        & "$PSScriptRoot\vm-points.ps1" list
        if ($LASTEXITCODE -ne 0) { throw "Could not list VM restore points." }

        Write-Host ""
        Write-Host "============== CLUSTER RESTORE POINTS =============" -ForegroundColor Cyan
        & "$PSScriptRoot\cluster-points.ps1" list
        if ($LASTEXITCODE -ne 0) { throw "Could not list Velero restore points." }
        return
    }

    Require-Name
    $ClusterName = $Name.ToLower()

    switch ($Action) {
        "create" {
            if ($Level -eq "vm" -or $Level -eq "both") {
                & "$PSScriptRoot\vm-points.ps1" create $Name
            }

            if ($Level -eq "cluster" -or $Level -eq "both") {
                # vm-points create already restarts ONLY the K3s nodes and waits
                # for Kubernetes. cluster-points independently verifies this as
                # well and never starts Jenkins.
                & "$PSScriptRoot\cluster-points.ps1" create $ClusterName
            }

            Write-Host ""
            Write-Host "Restore point '$Name' created at level '$Level'." -ForegroundColor Green
            if ($Level -eq "both") {
                Write-Host "Final VM state: K3s nodes running; Jenkins stopped." -ForegroundColor Yellow
            }
        }

        "restore" {
            if ($Level -eq "vm") {
                & "$PSScriptRoot\vm-points.ps1" restore $Name
            }
            elseif ($Level -eq "cluster") {
                & "$PSScriptRoot\cluster-points.ps1" restore $ClusterName
            }
            else {
                throw "Choose exactly one restore mechanism: -Level vm or -Level cluster. VM rollback and Velero restore must not be combined."
            }
        }

        "delete" {
            if ($Level -eq "vm" -or $Level -eq "both") {
                & "$PSScriptRoot\vm-points.ps1" delete $Name
            }

            if ($Level -eq "cluster" -or $Level -eq "both") {
                & "$PSScriptRoot\cluster-points.ps1" delete $ClusterName
            }

            Write-Host "Restore point '$Name' deleted at level '$Level'." -ForegroundColor Green
        }
    }
}
finally {
    Pop-Location
}
