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

    Write-Host "[1/5] Creating/provisioning k3s-master..." -ForegroundColor Cyan
    vagrant up k3s-master
    if ($LASTEXITCODE -ne 0) { throw "Failed to create/start k3s-master." }

    Write-Host "[2/5] Creating/provisioning k3s-worker1..." -ForegroundColor Cyan
    vagrant up k3s-worker1
    if ($LASTEXITCODE -ne 0) { throw "Failed to create/start k3s-worker1." }

    Write-Host "[3/5] Creating/provisioning k3s-worker2..." -ForegroundColor Cyan
    vagrant up k3s-worker2
    if ($LASTEXITCODE -ne 0) { throw "Failed to create/start k3s-worker2." }

    Write-Host "[4/5] Installing Kubernetes platform components locally on k3s-master..." -ForegroundColor Cyan
    Write-Host "      Ansible uses connection=local; no Vagrant SSH private keys are required." -ForegroundColor DarkGray

    $extraVars = "metallb_pool_start=$env:METALLB_POOL_START metallb_pool_end=$env:METALLB_POOL_END"
    vagrant ssh k3s-master -c "sudo ansible-playbook /vagrant/ansible/site.yml --extra-vars '$extraVars'"
    if ($LASTEXITCODE -ne 0) {
        throw "Ansible platform configuration failed. Run: vagrant ssh k3s-master -c `"sudo ansible-playbook /vagrant/ansible/site.yml --extra-vars '$extraVars' -vv`""
    }

    Write-Host "[5/5] Generating local and remote kubeconfig files..." -ForegroundColor Cyan
    & "$PSScriptRoot\get-kubeconfig.ps1"

    Write-Host ""
    Write-Host "Cluster is ready." -ForegroundColor Green
    & "$PSScriptRoot\status.ps1"

    Write-Host ""
    Write-Host "Remote Kubernetes API:" -ForegroundColor Cyan
    Write-Host "  https://$($env:K3S_API_LAN_IP):6443"
    Write-Host "Remote kubeconfig:"
    Write-Host "  .kube\remote-kubeconfig.yaml"
}
finally {
    Pop-Location
}
