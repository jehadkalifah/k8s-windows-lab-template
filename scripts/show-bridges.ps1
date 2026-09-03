$ErrorActionPreference = "Stop"

. "$PSScriptRoot\find-vboxmanage.ps1"

$VBoxManage = Get-VBoxManagePath

Write-Host "Using VBoxManage:" -ForegroundColor DarkGray
Write-Host "  $VBoxManage" -ForegroundColor DarkGray
Write-Host ""

Write-Host "Available VirtualBox bridged adapters:" -ForegroundColor Cyan
Write-Host ""

$adapters = & $VBoxManage list bridgedifs |
    Select-String '^Name:' |
    ForEach-Object {
        $_.Line -replace '^Name:\s*', ''
    }

if (-not $adapters) {
    Write-Host "No bridged adapters were returned by VirtualBox." -ForegroundColor Yellow
    Write-Host "Check that your Windows network adapters are enabled and that VirtualBox networking is installed correctly."
    exit 1
}

$adapters | ForEach-Object {
    Write-Host " - $_"
}
