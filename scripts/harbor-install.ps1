$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $RepoRoot
try {
    & "$PSScriptRoot\deploy.ps1" harbor
}
finally {
    Pop-Location
}
