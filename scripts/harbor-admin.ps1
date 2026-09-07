$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $RepoRoot
try {
    vagrant ssh k3s-master -c "sudo bash /vagrant/deployments/harbor/admin.sh"
    if ($LASTEXITCODE -ne 0) {
        throw "Could not retrieve Harbor admin credentials."
    }
}
finally {
    Pop-Location
}
