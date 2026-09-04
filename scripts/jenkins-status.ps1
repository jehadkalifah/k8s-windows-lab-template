$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot\load-config.ps1"

Push-Location $RepoRoot
try {
    Write-Host "=== Jenkins Vagrant VM ===" -ForegroundColor Cyan
    vagrant status jenkins

    $running = (vagrant status jenkins --machine-readable | Select-String ",state,running") -ne $null

    if ($running) {
        Write-Host ""
        Write-Host "=== Jenkins service ===" -ForegroundColor Cyan
        vagrant ssh jenkins -c "sudo systemctl --no-pager --full status jenkins | sed -n '1,14p'"

        Write-Host ""
        Write-Host "=== Jenkins local path ===" -ForegroundColor Cyan
        vagrant ssh jenkins -c "curl -fsSI http://127.0.0.1:8080/jenkins/login | head -1"

        Write-Host ""
        Write-Host "=== Jenkins bridged backend ===" -ForegroundColor Cyan
        Write-Host "http://$($env:JENKINS_LAN_IP):8080/jenkins/"
    }

    $masterRunning = (vagrant status k3s-master --machine-readable | Select-String ",state,running") -ne $null
    if ($masterRunning) {
        Write-Host ""
        Write-Host "=== Kubernetes external backend bridge ===" -ForegroundColor Cyan
        vagrant ssh k3s-master -c "sudo kubectl -n jenkins get service jenkins-external-svc -o wide 2>/dev/null || true"
        vagrant ssh k3s-master -c "sudo kubectl -n jenkins get endpointslice jenkins-external -o wide 2>/dev/null || true"
        vagrant ssh k3s-master -c "sudo kubectl -n jenkins get httproute jenkins-http-route -o wide 2>/dev/null || true"

        Write-Host ""
        Write-Host "=== Cluster -> Jenkins VM connectivity ===" -ForegroundColor Cyan
        vagrant ssh k3s-master -c "curl -fsSI --max-time 5 http://$($env:JENKINS_LAN_IP):8080/jenkins/login | head -1 || true"
    }
}
finally {
    Pop-Location
}
