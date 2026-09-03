param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet("cert-manager","istio")]
    [string]$Component
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $RepoRoot
try {
    switch ($Component) {
        "cert-manager" {
            vagrant ssh k3s-master -c "sudo bash /vagrant/deployments/cert-manager/status.sh"
            if ($LASTEXITCODE -ne 0) {
                throw "Could not read cert-manager deployment status."
            }
        }

        "istio" {
            vagrant ssh k3s-master -c "sudo bash /vagrant/deployments/istio/status.sh"
            if ($LASTEXITCODE -ne 0) {
                throw "Could not read Istio deployment status."
            }
        }
    }
}
finally {
    Pop-Location
}
