$ErrorActionPreference = "Stop"
. "$PSScriptRoot\load-config.ps1"
Write-Host "Testing https://$($env:K3S_API_LAN_IP):6443 ..." -ForegroundColor Cyan
$result = Test-NetConnection $env:K3S_API_LAN_IP -Port 6443
if ($result.TcpTestSucceeded) {
    Write-Host "PASS: Kubernetes API TCP/6443 is reachable." -ForegroundColor Green
} else {
    Write-Host "FAIL: Kubernetes API TCP/6443 is not reachable." -ForegroundColor Red
    exit 1
}
