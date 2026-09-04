param([string]$Name = "lab-clean-backup")
$ErrorActionPreference = "Stop"

Write-Host "Restoring Kubernetes/Velero backup '$Name'. Jenkins is excluded and will not be started." -ForegroundColor Cyan
& "$PSScriptRoot\cluster-points.ps1" restore $Name.ToLower()
