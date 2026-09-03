$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot\load-config.ps1"
Push-Location $RepoRoot
try {
    Write-Host "Kubernetes lab network configuration" -ForegroundColor Cyan
    Write-Host "  Bridge:       $env:K8S_BRIDGE_ADAPTER"
    Write-Host "  Master LAN:   $env:K3S_MASTER_LAN_IP"
    Write-Host "  Worker 1 LAN: $env:K3S_WORKER1_LAN_IP"
    Write-Host "  Worker 2 LAN: $env:K3S_WORKER2_LAN_IP"
    Write-Host "  API LAN:      https://$($env:K3S_API_LAN_IP):6443"
    Write-Host "  MetalLB:      $env:METALLB_POOL_START - $env:METALLB_POOL_END"
    Write-Host ""

    vagrant up k3s-master
    if ($LASTEXITCODE -ne 0) { throw "Failed to create/start k3s-master." }
    vagrant up k3s-worker1
    if ($LASTEXITCODE -ne 0) { throw "Failed to create/start k3s-worker1." }
    vagrant up k3s-worker2
    if ($LASTEXITCODE -ne 0) { throw "Failed to create/start k3s-worker2." }

    $extraVars = "metallb_pool_start=$env:METALLB_POOL_START metallb_pool_end=$env:METALLB_POOL_END"
    vagrant ssh k3s-master -c "sudo ansible-playbook -i /vagrant/ansible/inventory.ini /vagrant/ansible/site.yml --extra-vars '$extraVars'"
    if ($LASTEXITCODE -ne 0) { throw "Ansible platform configuration failed." }

    & "$PSScriptRoot\get-kubeconfig.ps1"
    Write-Host ""
    Write-Host "Cluster is ready." -ForegroundColor Green
    & "$PSScriptRoot\status.ps1"
    Write-Host ""
    Write-Host "Remote API: https://$($env:K3S_API_LAN_IP):6443" -ForegroundColor Cyan
    Write-Host "Remote kubeconfig: .kube\remote-kubeconfig.yaml"
}
finally { Pop-Location }
