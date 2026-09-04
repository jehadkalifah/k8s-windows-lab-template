$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $RepoRoot
try {
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host " KEYCLOAK TEMPORARY ADMIN" -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan

    $username = (
        vagrant ssh k3s-master -c "sudo kubectl -n keycloak get secret keycloak-initial-admin -o jsonpath='{.data.username}' | base64 -d"
    ).Trim()

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($username)) {
        throw "Could not retrieve keycloak-initial-admin username."
    }

    $password = (
        vagrant ssh k3s-master -c "sudo kubectl -n keycloak get secret keycloak-initial-admin -o jsonpath='{.data.password}' | base64 -d"
    ).Trim()

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($password)) {
        throw "Could not retrieve keycloak-initial-admin password."
    }

    Write-Host ""
    Write-Host "Username: $username"
    Write-Host "Password: $password"
    Write-Host ""
    Write-Host "This is a temporary bootstrap admin. Create a permanent admin account and remove/rotate temporary access." -ForegroundColor Yellow
}
finally {
    Pop-Location
}
