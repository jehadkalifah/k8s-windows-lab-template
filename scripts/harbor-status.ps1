$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $RepoRoot
try {
    & "$PSScriptRoot\deployment-status.ps1" harbor
}
finally {
    Pop-Location
}
