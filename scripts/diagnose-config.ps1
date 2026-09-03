$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Vagrantfile = Join-Path $RepoRoot "Vagrantfile"
$configFile = Join-Path $PSScriptRoot "lab-config.ps1"

Write-Host "=== Local config ===" -ForegroundColor Cyan
if (Test-Path $configFile) {
    Write-Host "PASS: scripts\lab-config.ps1 exists." -ForegroundColor Green
    . $configFile
    Write-Host "K8S_BRIDGE_ADAPTER = $env:K8S_BRIDGE_ADAPTER"
    Write-Host "K3S_FLANNEL_IFACE = $env:K3S_FLANNEL_IFACE"
}
else {
    Write-Host "FAIL: scripts\lab-config.ps1 does not exist." -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Vagrantfile ===" -ForegroundColor Cyan
$content = Get-Content $Vagrantfile -Raw

if ($content -match 'K8S_BRIDGE_ADAPTER is not configured\.' -and
    $content -notmatch 'commands_requiring_bridge') {
    Write-Host "FAIL: This is the OLD Vagrantfile with the unconditional bridge abort." -ForegroundColor Red
}
elseif ($content -match 'commands_requiring_bridge') {
    Write-Host "PASS: bridge is required only for up/reload/provision." -ForegroundColor Green
}
elseif ($content -match 'if bridge_configured') {
    Write-Host "PASS: bridged NIC is conditional." -ForegroundColor Green
}
else {
    Write-Host "WARNING: Vagrantfile bridge behavior could not be identified." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "show-bridges.ps1 only LISTS adapters; it does not set K8S_BRIDGE_ADAPTER." -ForegroundColor Yellow
Write-Host "To load your config manually:"
Write-Host "  . .\scripts\lab-config.ps1"


Write-Host ""
Write-Host "=== Flannel design ===" -ForegroundColor Cyan
Write-Host "eth0 = VirtualBox NAT (must NOT be used for Flannel)"
Write-Host "eth1 = 192.168.56.0/24 host-only inter-node network"
Write-Host "eth2 = 192.168.100.0/24 physical LAN"
Write-Host "Expected K3S_FLANNEL_IFACE = eth1"
