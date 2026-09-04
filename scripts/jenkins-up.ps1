$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot\load-config.ps1"

Push-Location $RepoRoot
try {
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host " JENKINS EXTERNAL VM" -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host "Management IP: $env:JENKINS_MGMT_IP"
    Write-Host "LAN/backend IP: $env:JENKINS_LAN_IP"
    Write-Host "Jenkins: $env:JENKINS_VERSION"
    Write-Host "Context path: /jenkins"
    Write-Host ""

    vagrant up jenkins
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create/start Jenkins VM."
    }

    Write-Host ""
    Write-Host "Checking Jenkins service..." -ForegroundColor Cyan
    vagrant ssh jenkins -c "sudo systemctl is-active jenkins && curl -fsSI http://127.0.0.1:8080/jenkins/login | head -1"
    if ($LASTEXITCODE -ne 0) {
        throw "Jenkins VM is running but Jenkins service/path validation failed."
    }

    Write-Host ""
    Write-Host "Jenkins VM is ready." -ForegroundColor Green
    Write-Host "Direct backend:"
    Write-Host "  http://$($env:JENKINS_LAN_IP):8080/jenkins/"
    Write-Host ""
    Write-Host "If the K3s Gateway is running, publish it with:"
    Write-Host "  .\scripts\publish.ps1 jenkins"
}
finally {
    Pop-Location
}
