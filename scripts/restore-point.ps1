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

        Write-Host ""
        Write-Host "============== CLUSTER RESTORE POINTS =============" -ForegroundColor Cyan
        & "$PSScriptRoot\cluster-points.ps1" list
        return
    }

    Require-Name

    switch ($Action) {
        "create" {
            if ($Level -eq "vm" -or $Level -eq "both") {
                & "$PSScriptRoot\vm-points.ps1" create $Name
            }

            if ($Level -eq "cluster" -or $Level -eq "both") {
                if ($Level -eq "both") {
                    . "$PSScriptRoot\load-config.ps1"
                    Write-Host "Starting VMs before the Velero backup..." -ForegroundColor Cyan
                    vagrant up --no-provision
                    if ($LASTEXITCODE -ne 0) { throw "Could not start VMs before Velero backup." }
                }

                & "$PSScriptRoot\cluster-points.ps1" create $Name.ToLower()
            }
        }

        "restore" {
            if ($Level -eq "vm") {
                & "$PSScriptRoot\vm-points.ps1" restore $Name
            }
            elseif ($Level -eq "cluster") {
                & "$PSScriptRoot\cluster-points.ps1" restore $Name.ToLower()
            }
            else {
                throw "Choose exactly one restore mechanism: -Level vm or -Level cluster."
            }
        }

        "delete" {
            if ($Level -eq "vm" -or $Level -eq "both") {
                & "$PSScriptRoot\vm-points.ps1" delete $Name
            }

            if ($Level -eq "cluster" -or $Level -eq "both") {
                & "$PSScriptRoot\cluster-points.ps1" delete $Name.ToLower()
            }
        }
    }
}
finally {
    Pop-Location
}
