param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet("cert-manager","istio")]
    [string]$Component,

    [switch]$PurgePrerequisites
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $RepoRoot
try {
    switch ($Component) {
        "cert-manager" {
            $purge = if ($PurgePrerequisites) { "1" } else { "0" }
            vagrant ssh k3s-master -c "sudo env PURGE_CRDS=$purge bash /vagrant/deployments/cert-manager/remove.sh"
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to remove cert-manager."
            }
        }

        "istio" {
            $purge = if ($PurgePrerequisites) { "1" } else { "0" }
            vagrant ssh k3s-master -c "sudo env PURGE_PREREQUISITES=$purge bash /vagrant/deployments/istio/remove.sh"
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to remove Istio deployment."
            }
        }
    }
}
finally {
    Pop-Location
}
