Write-Host ""
Write-Host "Kubernetes Windows Lab" -ForegroundColor Cyan
Write-Host "======================" -ForegroundColor Cyan
Write-Host ""
Write-Host "STAGE 1 - BASE CLUSTER"
Write-Host "  . .\scripts\lab-config.ps1"
Write-Host "  .\scripts\up.ps1"
Write-Host ""
Write-Host "STAGE 2 - DEPLOYMENTS"
Write-Host "  .\scripts\deploy.ps1 cert-manager"
Write-Host "  .\scripts\deploy.ps1 istio"
Write-Host "  .\scripts\deployment-status.ps1 istio"
Write-Host "  .\scripts\remove-deployment.ps1 istio"
Write-Host ""
Write-Host "LIFECYCLE"
Write-Host "  .\scripts\run.ps1"
Write-Host "  .\scripts\down.ps1"
Write-Host "  .\scripts\suspend.ps1"
Write-Host "  .\scripts\resume.ps1"
Write-Host "  .\scripts\destroy.cmd"


Write-Host ""
Write-Host "ALL STAGE 2 COMPONENTS"
Write-Host "  .\scripts\deploy.ps1 all"
Write-Host "  .\scripts\deployment-status.ps1 all"

Write-Host ""
Write-Host "NOTE" -ForegroundColor Yellow
Write-Host "  Kubernetes cluster lifecycle commands exclude Jenkins."
Write-Host "  Start Jenkins separately with: .\scripts\jenkins-up.ps1"
