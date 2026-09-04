$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $RepoRoot
try {
    Write-Host "Jenkins initial administrator password:" -ForegroundColor Cyan
    vagrant ssh jenkins -c "sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
    if ($LASTEXITCODE -ne 0) {
        throw "Could not read the Jenkins initial admin password."
    }
}
finally {
    Pop-Location
}
