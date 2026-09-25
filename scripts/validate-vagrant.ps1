$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $RepoRoot

try {
    Write-Host "Validating Vagrantfile without loading lab-config.ps1..." -ForegroundColor Cyan

    $vagrant = Get-Command vagrant -ErrorAction SilentlyContinue
    if ($null -eq $vagrant) {
        Write-Host "WARNING: vagrant is not installed in this environment; skipping Vagrantfile validation." -ForegroundColor Yellow
        return
    }

    $oldBridge = $env:K8S_BRIDGE_ADAPTER
    Remove-Item Env:K8S_BRIDGE_ADAPTER -ErrorAction SilentlyContinue

    try {
        vagrant validate
        if ($LASTEXITCODE -ne 0) {
            throw "Vagrantfile validation failed."
        }

        Write-Host "Vagrantfile is valid without K8S_BRIDGE_ADAPTER." -ForegroundColor Green
        Write-Host "Destroy/status/snapshot commands can therefore evaluate it safely."
    }
    finally {
        if ($null -ne $oldBridge) {
            $env:K8S_BRIDGE_ADAPTER = $oldBridge
        }
    }
}
finally {
    Pop-Location
}
