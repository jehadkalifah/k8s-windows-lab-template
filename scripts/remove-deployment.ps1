param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet("argocd","cert-manager","istio","longhorn","monitoring","velero")]
    [string]$Component,

    [switch]$PurgePrerequisites,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $RepoRoot
try {
    $forceValue = if ($Force) { "1" } else { "0" }

    switch ($Component) {
        "argocd" {
            vagrant ssh k3s-master -c "sudo bash /vagrant/deployments/argocd/remove.sh"
        }
        "cert-manager" {
            $purge = if ($PurgePrerequisites) { "1" } else { "0" }
            vagrant ssh k3s-master -c "sudo env PURGE_CRDS=$purge bash /vagrant/deployments/cert-manager/remove.sh"
        }
        "istio" {
            $purge = if ($PurgePrerequisites) { "1" } else { "0" }
            vagrant ssh k3s-master -c "sudo env PURGE_PREREQUISITES=$purge bash /vagrant/deployments/istio/remove.sh"
        }
        "longhorn" {
            vagrant ssh k3s-master -c "sudo env FORCE=$forceValue bash /vagrant/deployments/longhorn/remove.sh"
        }
        "monitoring" {
            vagrant ssh k3s-master -c "sudo bash /vagrant/deployments/monitoring/remove.sh"
        }
        "velero" {
            vagrant ssh k3s-master -c "sudo env FORCE=$forceValue bash /vagrant/deployments/velero/remove.sh"
        }
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to remove '$Component'."
    }
}
finally {
    Pop-Location
}
