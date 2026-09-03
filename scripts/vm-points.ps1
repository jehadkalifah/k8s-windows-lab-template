param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet("create","list","restore","delete")]
    [string]$Action,

    [Parameter(Mandatory=$false, Position=1)]
    [string]$Name
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$VMs = @("k3s-master", "k3s-worker1", "k3s-worker2")

function Require-Name {
    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "A restore point name is required for action '$Action'."
    }
    if ($Name -notmatch '^[a-zA-Z0-9._-]+$') {
        throw "Use only letters, numbers, dot, underscore and hyphen in VM restore point names."
    }
}

Push-Location $RepoRoot
try {
    switch ($Action) {
        "create" {
            Require-Name

            Write-Host "Halting all VMs for a consistent VM restore point..." -ForegroundColor Cyan
            vagrant halt
            if ($LASTEXITCODE -ne 0) { throw "vagrant halt failed." }

            foreach ($vm in $VMs) {
                Write-Host "Creating '$Name' for $vm..." -ForegroundColor Cyan
                vagrant snapshot save $vm $Name
                if ($LASTEXITCODE -ne 0) { throw "Snapshot creation failed for $vm." }
            }

            Write-Host "VM restore point '$Name' created." -ForegroundColor Green
        }

        "list" {
            foreach ($vm in $VMs) {
                Write-Host ""
                Write-Host "=== $vm ===" -ForegroundColor Cyan
                vagrant snapshot list $vm
            }
        }

        "restore" {
            Require-Name

            # vagrant up is used after restore; load LAN config before that.
            . "$PSScriptRoot\load-config.ps1"

            Write-Host "Halting all VMs..." -ForegroundColor Cyan
            vagrant halt

            foreach ($vm in $VMs) {
                Write-Host "Restoring '$Name' on $vm..." -ForegroundColor Cyan
                vagrant snapshot restore $vm $Name
                if ($LASTEXITCODE -ne 0) { throw "Snapshot restore failed for $vm." }
            }

            Write-Host "Starting restored VMs..." -ForegroundColor Cyan
            vagrant up --no-provision
            if ($LASTEXITCODE -ne 0) { throw "Failed to start restored VMs." }

            & "$PSScriptRoot\get-kubeconfig.ps1"
            & "$PSScriptRoot\status.ps1"

            Write-Host "VM restore point '$Name' restored." -ForegroundColor Green
        }

        "delete" {
            Require-Name

            foreach ($vm in $VMs) {
                Write-Host "Deleting '$Name' from $vm..." -ForegroundColor Yellow
                vagrant snapshot delete $vm $Name
            }

            Write-Host "VM restore point '$Name' deleted." -ForegroundColor Green
        }
    }
}
finally {
    Pop-Location
}
