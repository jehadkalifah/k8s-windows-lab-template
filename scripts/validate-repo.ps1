$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

$inventory = Get-Content (Join-Path $RepoRoot "ansible\inventory.ini") -Raw
$site = Get-Content (Join-Path $RepoRoot "ansible\site.yml") -Raw
$up = Get-Content (Join-Path $RepoRoot "scripts\up.ps1") -Raw

$failed = $false

if ($inventory -match "private_key" -or $inventory -match "\.vagrant/machines") {
    Write-Host "FAIL: Ansible inventory still references Vagrant private keys." -ForegroundColor Red
    $failed = $true
} else {
    Write-Host "PASS: Ansible inventory contains no Vagrant private-key dependency." -ForegroundColor Green
}

if ($inventory -match "ansible_connection=local" -and $site -match "connection:\s*local") {
    Write-Host "PASS: Ansible platform configuration runs locally on k3s-master." -ForegroundColor Green
} else {
    Write-Host "FAIL: Local-only Ansible configuration is missing." -ForegroundColor Red
    $failed = $true
}

if ($up -match "sudo ansible-playbook /vagrant/ansible/site.yml") {
    Write-Host "PASS: up.ps1 invokes the local platform playbook." -ForegroundColor Green
} else {
    Write-Host "FAIL: up.ps1 does not invoke the expected playbook." -ForegroundColor Red
    $failed = $true
}

if ($failed) { exit 1 }
Write-Host "Repository validation passed." -ForegroundColor Green
