$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot\load-config.ps1"

Push-Location $RepoRoot
try {
    vagrant provision jenkins
    if ($LASTEXITCODE -ne 0) {
        throw "Jenkins reprovision failed."
    }
    & "$PSScriptRoot\jenkins-status.ps1"
}
finally {
    Pop-Location
}
