$ErrorActionPreference = "Stop"

Write-Host "This destroys all three VMs and their local cluster data." -ForegroundColor Yellow
$confirmation = Read-Host "Type DESTROY to continue"

if ($confirmation -ne "DESTROY") {
    Write-Host "Cancelled."
    exit 0
}

vagrant destroy -f

if (Test-Path ".kube") {
    Remove-Item ".kube" -Recurse -Force
}

if (Test-Path ".k3s-token") {
    Remove-Item ".k3s-token" -Force
}
