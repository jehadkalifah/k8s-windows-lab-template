param(
    [ValidateSet("ensure","status")]
    [string]$Action = "status"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $RepoRoot
try {
    switch ($Action) {
        "ensure" {
            vagrant ssh k3s-master -c "sudo bash /vagrant/deployments/k3s-local-storage/ensure.sh"
        }
        "status" {
            vagrant ssh k3s-master -c "sudo bash /vagrant/deployments/k3s-local-storage/status.sh"
        }
    }

    if ($LASTEXITCODE -ne 0) {
        throw "K3s local-storage action '$Action' failed."
    }
}
finally {
    Pop-Location
}
