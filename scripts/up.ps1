$ErrorActionPreference = "Stop"

. "$PSScriptRoot\load-config.ps1"

Write-Host "Using bridged adapter: $env:K8S_BRIDGE_ADAPTER" -ForegroundColor Cyan
Write-Host "MetalLB pool: $env:METALLB_POOL_START - $env:METALLB_POOL_END" -ForegroundColor Cyan
Write-Host ""

Write-Host "Starting control-plane VM..." -ForegroundColor Cyan
vagrant up k3s-master

Write-Host "Starting worker VMs..." -ForegroundColor Cyan
vagrant up k3s-worker1
vagrant up k3s-worker2

Write-Host "Running Ansible platform configuration..." -ForegroundColor Cyan

$extraVars = "metallb_pool_start=$env:METALLB_POOL_START metallb_pool_end=$env:METALLB_POOL_END"

vagrant ssh k3s-master -c "sudo ansible-playbook -i /vagrant/ansible/inventory.ini /vagrant/ansible/site.yml --extra-vars '$extraVars'"

& "$PSScriptRoot\get-kubeconfig.ps1"

Write-Host ""
Write-Host "Cluster is ready." -ForegroundColor Green

& "$PSScriptRoot\status.ps1"

Write-Host ""
Write-Host "Bridged/LAN addresses:" -ForegroundColor Cyan
vagrant ssh k3s-master -c "ip -br -4 addr"
vagrant ssh k3s-worker1 -c "ip -br -4 addr"
vagrant ssh k3s-worker2 -c "ip -br -4 addr"
