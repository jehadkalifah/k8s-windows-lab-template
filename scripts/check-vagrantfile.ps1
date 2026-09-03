$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Vagrantfile = Join-Path $RepoRoot "Vagrantfile"

$content = Get-Content $Vagrantfile -Raw

Write-Host "Checking Vagrantfile..." -ForegroundColor Cyan

if ($content -match 'K8S_BRIDGE_ADAPTER is not configured' -or
    $content -match 'abort\s+<<~MSG') {
    Write-Host "FAIL: old hard bridge abort is still present." -ForegroundColor Red
    exit 1
}

if ($content -match 'if bridge_configured') {
    Write-Host "PASS: bridged NIC is conditional." -ForegroundColor Green
}
else {
    Write-Host "WARNING: conditional bridge block was not found." -ForegroundColor Yellow
}

Write-Host "Vagrantfile maintenance commands should no longer require bridge variables." -ForegroundColor Green
