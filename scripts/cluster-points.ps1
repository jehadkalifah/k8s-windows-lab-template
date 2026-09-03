param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet("create","list","restore","delete","describe")]
    [string]$Action,

    [Parameter(Mandatory=$false, Position=1)]
    [string]$Name
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $RepoRoot


function Require-Name {
    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "A restore point name is required for action '$Action'."
    }
    if ($Name -notmatch '^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$') {
        throw "Velero backup names must use lowercase letters, numbers, dot and hyphen."
    }
}

switch ($Action) {
    "create" {
        Require-Name
        Write-Host "Creating Velero backup '$Name'..." -ForegroundColor Cyan
        vagrant ssh k3s-master -c "velero backup create $Name --include-cluster-scoped-resources=true --exclude-namespaces velero --default-volumes-to-fs-backup --wait"
        vagrant ssh k3s-master -c "velero backup describe $Name --details"
    }

    "list" {
        vagrant ssh k3s-master -c "velero backup get"
    }

    "describe" {
        Require-Name
        vagrant ssh k3s-master -c "velero backup describe $Name --details"
    }

    "restore" {
        Require-Name
        $RestoreName = "$Name-restore-$(Get-Date -Format 'yyyyMMddHHmmss')"
        Write-Host "Restoring Velero backup '$Name'..." -ForegroundColor Cyan
        vagrant ssh k3s-master -c "velero restore create $RestoreName --from-backup $Name --wait"
        vagrant ssh k3s-master -c "velero restore describe $RestoreName --details"
    }

    "delete" {
        Require-Name
        Write-Host "Deleting Velero backup '$Name'..." -ForegroundColor Yellow
        vagrant ssh k3s-master -c "velero backup delete $Name --confirm"
    }
}

Pop-Location
