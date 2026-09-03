$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $RepoRoot
try {
    vagrant ssh k3s-master -c "sudo bash /vagrant/deployments/publishing/remove.sh"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to remove publishing HTTPRoutes."
    }
}
finally {
    Pop-Location
}
