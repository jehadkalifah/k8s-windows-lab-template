$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Vagrantfile = Join-Path $RepoRoot "Vagrantfile"

$content = Get-Content $Vagrantfile -Raw

Write-Host "Checking Vagrantfile..." -ForegroundColor Cyan

if ($content -match 'K8S_BRIDGE_ADAPTER is not configured') {
    Write-Host "FAIL: old hard bridge abort is still present." -ForegroundColor Red
    exit 1
}

if ($content -match 'if bridge_configured') {
    Write-Host "PASS: bridged NIC is conditional." -ForegroundColor Green
}
else {
    Write-Host "WARNING: conditional bridge block was not found." -ForegroundColor Yellow
}

if ($content -match 'Vagrant\.has_plugin\?\("vagrant-disksize"\)' -and
    $content -match 'vm\.disksize\.size') {
    Write-Host "PASS: disksize plugin guard and per-VM disk sizing are present." -ForegroundColor Green
}
else {
    Write-Host "WARNING: disksize plugin guard or per-VM disk sizing was not found." -ForegroundColor Yellow
}

Write-Host "Vagrantfile maintenance commands should no longer require bridge variables." -ForegroundColor Green
