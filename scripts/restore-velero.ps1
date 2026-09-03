param([string]$Name = "lab-clean-backup")
$ErrorActionPreference = "Stop"
& "$PSScriptRoot\cluster-points.ps1" restore $Name.ToLower()
