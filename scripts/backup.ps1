param([string]$Name = "lab-clean-backup")
$ErrorActionPreference = "Stop"

Write-Host "Creating Kubernetes/Velero backup '$Name'. Jenkins is excluded and will not be started." -ForegroundColor Cyan
& "$PSScriptRoot\cluster-points.ps1" create $Name.ToLower()
