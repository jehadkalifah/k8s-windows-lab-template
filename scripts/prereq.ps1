$ErrorActionPreference = "Stop"

$commands = @("vagrant", "git")

foreach ($cmd in $commands) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        throw "$cmd is not installed or not available in PATH."
    }
}

. "$PSScriptRoot\find-vboxmanage.ps1"
$VBoxManage = Get-VBoxManagePath

Write-Host "Vagrant:    $(vagrant --version)" -ForegroundColor Green
Write-Host "VirtualBox: $(& $VBoxManage --version)" -ForegroundColor Green
Write-Host "Git:        $(git --version)" -ForegroundColor Green

Write-Host ""
Write-Host "VirtualBox executable:" -ForegroundColor Cyan
Write-Host "  $VBoxManage"

Write-Host ""
& "$PSScriptRoot\show-bridges.ps1"

Write-Host ""
if (-not (Test-Path "$PSScriptRoot\lab-config.ps1")) {
    Write-Host "scripts\lab-config.ps1 does not exist yet." -ForegroundColor Yellow
    Write-Host "Create it with:"
    Write-Host "  Copy-Item .\scripts\lab-config.ps1.example .\scripts\lab-config.ps1"
}
else {
    Write-Host "scripts\lab-config.ps1 exists." -ForegroundColor Green
}
