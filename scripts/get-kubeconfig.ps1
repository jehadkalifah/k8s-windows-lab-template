$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$configFile = Join-Path $PSScriptRoot "lab-config.ps1"
if (Test-Path $configFile) { . $configFile }
Push-Location $RepoRoot
try {
    $kubeDir = Join-Path $RepoRoot ".kube"
    New-Item -ItemType Directory -Force -Path $kubeDir | Out-Null
    $raw = vagrant ssh k3s-master -c "sudo cat /etc/rancher/k3s/k3s.yaml"
    if ($LASTEXITCODE -ne 0) { throw "Could not read kubeconfig from k3s-master." }
    $yaml = $raw -join "`n"

    $localPath = Join-Path $kubeDir "lab-kubeconfig.yaml"
    $localContent = $yaml -replace "https://127\.0\.0\.1:6443", "https://192.168.56.10:6443"
    Set-Content -Path $localPath -Value $localContent -Encoding ascii
    Write-Host "Local kubeconfig: $localPath" -ForegroundColor Green

    if (-not [string]::IsNullOrWhiteSpace($env:K3S_API_LAN_IP)) {
        $remotePath = Join-Path $kubeDir "remote-kubeconfig.yaml"
        $remoteContent = $yaml -replace "https://127\.0\.0\.1:6443", "https://$($env:K3S_API_LAN_IP):6443"
        Set-Content -Path $remotePath -Value $remoteContent -Encoding ascii
        Write-Host "Remote kubeconfig: $remotePath" -ForegroundColor Green
        Write-Host "Remote API: https://$($env:K3S_API_LAN_IP):6443"
    }
}
finally { Pop-Location }
